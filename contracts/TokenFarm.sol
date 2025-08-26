// SPDX-License-Identifier: MIT
pragma solidity ^0.8.22;

import "./DappToken.sol";
import "./LPToken.sol";

/**
 * @title Proportional Token Farm
 * @notice Una granja de staking donde las recompensas se distribuyen proporcionalmente al total stakeado.
 */
contract TokenFarm {
    //
    // Variables de estado
    //
    string public name = "Proportional Token Farm";
    address public owner;
    DAppToken public dappToken;
    LPToken public lpToken;

    uint256 public constant REWARD_PER_BLOCK = 1e18; // Recompensa total por bloque (para todos los usuarios)
    uint256 public totalStakingBalance; // Total de tokens en staking

    address[] public stakers;
    mapping(address => uint256) public stakingBalance;
    mapping(address => uint256) public checkpoints; // bloque del último cálculo por usuario
    mapping(address => uint256) public pendingRewards; // DAPP pendientes por usuario
    mapping(address => bool) public hasStaked;
    mapping(address => bool) public isStaking;

    // Eventos
    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event RewardsClaimed(address indexed user, uint256 amount);
    event RewardsDistributed(address indexed caller, uint256 usersProcessed);

    // Constructor
    constructor(DAppToken _dappToken, LPToken _lpToken) {
        dappToken = _dappToken;
        lpToken = _lpToken;
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "TokenFarm: not owner");
        _;
    }

    /**
     * @notice Deposita tokens LP para staking.
     * @param _amount Cantidad de tokens LP a depositar.
     */
    function deposit(uint256 _amount) external {
        require(_amount > 0, "Deposit amount must be > 0");

        // 1) Primero actualizar recompensas con el balance anterior
        distributeRewards(msg.sender);

        // 2) Transferir tokens LP del usuario a este contrato
        lpToken.transferFrom(msg.sender, address(this), _amount);

        // 3) Actualizar balances
        stakingBalance[msg.sender] += _amount;
        totalStakingBalance += _amount;

        // 4) Registrar staker si es primera vez
        if (!hasStaked[msg.sender]) {
            stakers.push(msg.sender);
            hasStaked[msg.sender] = true;
        }
        isStaking[msg.sender] = true;

        // 5) Si no tenía checkpoint, inicializarlo (distributeRewards ya lo hace si estaba en 0)
        if (checkpoints[msg.sender] == 0) {
            checkpoints[msg.sender] = block.number;
        }

        emit Deposit(msg.sender, _amount);
    }

    /**
     * @notice Retira todos los tokens LP en staking.
     */
    function withdraw() external {
        require(isStaking[msg.sender], "User is not staking");

        uint256 balance = stakingBalance[msg.sender];
        require(balance > 0, "No LP to withdraw");

        // 1) Actualizar recompensas antes de modificar balances
        distributeRewards(msg.sender);

        // 2) Actualizar balances
        stakingBalance[msg.sender] = 0;
        totalStakingBalance -= balance;
        isStaking[msg.sender] = false;

        // 3) Transferir LP al usuario
        lpToken.transfer(msg.sender, balance);

        emit Withdraw(msg.sender, balance);
    }

    /**
     * @notice Reclama recompensas pendientes.
     */
    function claimRewards() external {
        uint256 pendingAmount = pendingRewards[msg.sender];
        require(pendingAmount > 0, "No rewards to claim");

        // Reiniciar pendientes antes de acuñar para evitar reentradas sobre el estado interno
        pendingRewards[msg.sender] = 0;

        // IMPORTANTE: El owner del DAppToken debe ser la Farm (o debe transferirse la propiedad a la Farm).
        dappToken.mint(msg.sender, pendingAmount);

        emit RewardsClaimed(msg.sender, pendingAmount);
    }

    /**
     * @notice Distribuye recompensas a todos los usuarios en staking.
     */
    function distributeRewardsAll() external onlyOwner {
        uint256 processed;
        for (uint256 i = 0; i < stakers.length; i++) {
            address user = stakers[i];
            if (isStaking[user] && stakingBalance[user] > 0) {
                distributeRewards(user);
                processed++;
            }
        }
        emit RewardsDistributed(msg.sender, processed);
    }

    /**
     * @notice Calcula y distribuye las recompensas proporcionalmente al staking total.
     *
     * Funcionamiento:
     * - Calcula bloques transcurridos desde el último checkpoint del usuario.
     * - share = stakingBalance[beneficiary] / totalStakingBalance
     * - reward = REWARD_PER_BLOCK * blocksPassed * share
     * - Acumula en pendingRewards[beneficiary] y actualiza checkpoint.
     */
    function distributeRewards(address beneficiary) private {
        uint256 last = checkpoints[beneficiary];

        // Primera vez: solo marca checkpoint y sale (evita regalar recompensas si aún no stakeó)
        if (last == 0) {
            checkpoints[beneficiary] = block.number;
            return;
        }
        // Nada que hacer si no han pasado bloques o no hay staking global
        if (block.number <= last || totalStakingBalance == 0) {
            return;
        }

        uint256 userBal = stakingBalance[beneficiary];
        // Si el usuario no tiene stake, solo avanzar checkpoint
        if (userBal == 0) {
            checkpoints[beneficiary] = block.number;
            return;
        }

        uint256 blocksPassed = block.number - last;

        // reward = RPB * blocksPassed * (userBal / totalStakingBalance)
        // Usar orden que evite pérdida de precisión: (RPB * blocks * userBal) / totalStaking
        uint256 reward = (REWARD_PER_BLOCK * blocksPassed * userBal) /
            totalStakingBalance;

        pendingRewards[beneficiary] += reward;
        checkpoints[beneficiary] = block.number;
    }
}
