// SPDX-License-Identifier: MIT
pragma solidity <=0.8.10;

import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface Structs {
    struct Val {
        uint256 value; // Mängd 
    }

    enum ActionType {
        Deposit, // skaffa tokens
        Withdraw, // låna tokens
        Transfer, // skicka balansen mellan konton
        Buy, // Köp en summa av en viss token (extern)
        Sell, // Sälj en summa av en viss token (extern)
        Trade, // Tradea tokens mot ett annat konto
        Liquidate, // Likvidera ett lån (undercollateraliserad) eller utgående konto
        Vaporize, // Använd överskotts-tokens för att nollställa ett helt negativt konto
        Call // Skicka godtycklig data till en address
    }

    enum AssetDenomination {
        Wei // Mängden är konverterad till "Wei"
    }

    enum AssetReference {
        Delta // Mängden är given som en delta från den nuvarande valutan
    }

    struct AssetAmount {
        bool sign; // Om detta är true ska den visa "positivt" eftersom bool(boolean) är ett false/true statement
        AssetDenomination denomination;
        AssetReference ref;
        uint256 value;
    }

    struct ActionArgs {
        ActionType actionType; // Här tar vi in addresserna vilket jag kommer visa nedan.
        uint256 accountId;
        AssetAmount amount;
        uint256 primaryMarketId;
        uint256 secondaryMarketId;
        address otherAddress;
        uint256 otherAccountId;
        bytes data;
    }

    struct Info {
        address owner; // Addressen som äger kontot
        uint256 number; // Ett nummer som låter ett konto hantera flera.
    }

    struct Wei {
        bool sign; // Om detta är true ska den visa "positivt" eftersom bool(boolean) är ett false/true statement
        uint256 value; // uint256 står för unsigned 256-bit integer alltså en 256-bits siffra (tillåter högst 256 bits 1 siffra är 1 bit)
    }
}

abstract contract DyDxPool is Structs {
    function getAccountWei(Info memory account, uint256 marketId)
        public
        view
        virtual
        returns (Wei memory);

    function operate(Info[] memory, ActionArgs[] memory) public virtual;
}

contract DyDxFlashLoan is Structs {
    DyDxPool pool = DyDxPool(0x1E0447b19BB6EcFdAe1e4AE1694b0C3659614e4e); // Addressen för DyDx Poolen vi kommer ta flashlånet ifrån

    address public WETH = 0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2; // (WETH/Wrapped Ether) Addressen vi kommer använda flashlånet i
    mapping(address => uint256) public currencies;

    constructor() {
        currencies[WETH] = 1;
    }

    modifier onlyPool() {
        require(
            msg.sender == address(pool),
            "FlashLoan: could be called by DyDx pool only"
        );
        _;
    }

    function tokenToMarketId(address token) public view returns (uint256) {
        uint256 marketId = currencies[token];
        require(marketId != 0, "FlashLoan: Unsupported token");
        return marketId - 1;
    }

    // DyDx kommer att kalla `callFunction(address sender, Info memory accountInfo, bytes memory data) public` efter medans `operate` kallelsen
    function flashloan(
        address token,
        uint256 amount,
        bytes memory data
    ) internal {
        IERC20(token).approve(address(pool), amount + 1);
        Info[] memory infos = new Info[](1);
        ActionArgs[] memory args = new ActionArgs[](3);

        infos[0] = Info(address(this), 0);

        AssetAmount memory wamt = AssetAmount(
            false,
            AssetDenomination.Wei,
            AssetReference.Delta,
            amount
        );
        ActionArgs memory withdraw;
        withdraw.actionType = ActionType.Withdraw;
        withdraw.accountId = 0;
        withdraw.amount = wamt;
        withdraw.primaryMarketId = tokenToMarketId(token);
        withdraw.otherAddress = address(this);

        args[0] = withdraw;

        ActionArgs memory call;
        call.actionType = ActionType.Call;
        call.accountId = 0;
        call.otherAddress = address(this);
        call.data = data;

        args[1] = call;

        ActionArgs memory deposit;
        AssetAmount memory damt = AssetAmount(
            true,
            AssetDenomination.Wei,
            AssetReference.Delta,
            amount + 1
        );
        deposit.actionType = ActionType.Deposit;
        deposit.accountId = 0;
        deposit.amount = damt;
        deposit.primaryMarketId = tokenToMarketId(token);
        deposit.otherAddress = address(this);

        args[2] = deposit;

        pool.operate(infos, args);
    }
}

contract Arbitrage is DyDxFlashLoan {
    IUniswapV2Router02 public immutable sRouter;
    IUniswapV2Router02 public immutable uRouter;
    IUniswapV2Router02 public immutable pRouter;

    address public owner;

    constructor(address _sRouter, address _uRouter, address _pRouter) {
        sRouter = IUniswapV2Router02(_sRouter); // Sushiswap alltså en exchange
        uRouter = IUniswapV2Router02(_uRouter); // Uniswap alltså en exchange
        pRouter = IUniswapV2Router02(_pRouter); // PancakeSwap en ny exchange jag lade till.
        owner = msg.sender;
    }

    function executeTrade(
        bool _startOnUniswap,
        address _token0,
        address _token1,
        uint256 _flashAmount
    ) external {
        uint256 balanceBefore = IERC20(_token0).balanceOf(address(this));

        bytes memory data = abi.encode(
            _startOnUniswap,
            _token0,
            _token1,
            _flashAmount,
            balanceBefore
        );

        flashloan(_token0, _flashAmount, data); // execution goes to `callFunction`
    }

    function callFunction(
        address, /* sender */
        Info calldata, /* accountInfo */
        bytes calldata data
    ) external onlyPool {
        (
            bool startOnUniswap,
            address token0,
            address token1,
            uint256 flashAmount,
            uint256 balanceBefore
        ) = abi.decode(data, (bool, address, address, uint256, uint256));

        uint256 balanceAfter = IERC20(token0).balanceOf(address(this));

        require(
            balanceAfter - balanceBefore == flashAmount,
            "contract did not get the loan"
        );

        // Use the money here!
        address[] memory path = new address[](2);

        path[0] = token0;
        path[1] = token1;

        if (startOnUniswap) {
            _swapOnUniswap(path, flashAmount, 0);

            path[0] = token1;
            path[1] = token0;

            _swapOnSushiswap(
                path,
                IERC20(token1).balanceOf(address(this)),
                (flashAmount + 1)
            );
        } else {
            _swapOnSushiswap(path, flashAmount, 0);

            path[0] = token1;
            path[1] = token0;

            _swapOnUniswap(
                path,
                IERC20(token1).balanceOf(address(this)),
                (flashAmount + 1)
            );
        }

        IERC20(token0).transfer(
            owner,
            IERC20(token0).balanceOf(address(this)) - (flashAmount + 1)
        );
    }

    // -- Interna Funktioner -- //

    function _swapOnPancakeSwap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal {
        require(
            IERC20(_path[0]).approve(address(pRouter), _amountIn),
            "PancakeSwap approval failed."
        );

        pRouter.swapExactTokensForTokens(
            _amountIn,
            _amountOut,
            _path,
            address(this),
            (block.timestamp + 1200)
        );
    }

    function _swapOnUniswap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal {
        require(
            IERC20(_path[0]).approve(address(uRouter), _amountIn),
            "Uniswap approval failed."
        );

        uRouter.swapExactTokensForTokens(
            _amountIn,
            _amountOut,
            _path,
            address(this),
            (block.timestamp + 1200)
        );
    }

    function _swapOnSushiswap(
        address[] memory _path,
        uint256 _amountIn,
        uint256 _amountOut
    ) internal {
        require(
            IERC20(_path[0]).approve(address(sRouter), _amountIn),
            "Sushiswap approval failed."
        );

        sRouter.swapExactTokensForTokens(
            _amountIn,
            _amountOut,
            _path,
            address(this),
            (block.timestamp + 1200)
        );
    }
}
