require("dotenv").config();
const config = require("../config.json");


const Big = require("big.js");
const Web3 = require("web3");
let web3;


if (!config.PROJECT_SETTINGS.isLocal) {
    web3 = new Web3(`wss://eth-mainnet.alchemyapi.io/v2/${process.env.ALCHEMY_API_KEY}`);
} else {
    web3 = new Web3("ws://127.0.0.1:7545");
}

const { ChainId, Token } = require("@uniswap/sdk");
const IUniswapV2Pair = require("@uniswap/v2-core/build/IUniswapV2Pair.json");
const IERC20 = require("@openzeppelin/contracts/build/contracts/ERC20.json");

async function getTokenAndContract(_token0Address, _token1Address, _token2Address) {
    const token0Contract = new web3.eth.Contract(IERC20.abi, _token0Address);
    const token1Contract = new web3.eth.Contract(IERC20.abi, _token1Address);
    const token2Contract = new web3.eth.Contract(IERC20.abi, _token2Address);

    const token0 = new Token(
        ChainId.MAINNET,
        _token0Address,
        await token0Contract.methods.decimals().call(),
        await token0Contract.methods.symbol().call(),
        await token0Contract.methods.name().call()
    );

    const token1 = new Token(
        ChainId.MAINNET,
        _token1Address,
        await token1Contract.methods.decimals().call(),
        await token1Contract.methods.symbol().call(),
        await token1Contract.methods.name().call()
    );

    const token2 = new Token(
        ChainId.MAINNET,
        _token2Address,
        await token2Contract.methods.decimals().call(),
        await token2Contract.methods.symbol().call(),
        await token2Contract.methods.name().call()
    );

    return { token0Contract, token1Contract, token2Contract, token0, token1, token2 };
}

async function getPairAddress(_V2Factory, _tokenA, _tokenB) {
    const pairAddress = await _V2Factory.methods.getPair(_tokenA, _tokenB).call();
    return pairAddress;
}

async function getPairContract(_V2Factory, _tokenA, _tokenB) {
    const pairAddress = await getPairAddress(_V2Factory, _tokenA, _tokenB);
    const pairContract = new web3.eth.Contract(IUniswapV2Pair.abi, pairAddress);
    return pairContract;
}

async function getReserves(_pairContract) {
    const reserves = await _pairContract.methods.getReserves().call();
    return [reserves.reserve0, reserves.reserve1];
}

async function calculatePrice(_pairContract) {
    const [reserve0, reserve1] = await getReserves(_pairContract);
    return Big(reserve0).div(Big(reserve1)).toString();
}

function calculateDifference(uPrice, sPrice) {
    return (((uPrice - sPrice) / sPrice) * 100).toFixed(2);
}

async function getEstimatedReturn(amount, routerPath, _tokenA, _tokenB) {
    const trade1 = await routerPath.methods.getAmountsOut(amount, [_tokenA, _tokenB]).call();
    const trade2 = await routerPath.methods.getAmountsOut(trade1[1], [_tokenB, _tokenA]).call();

    const amountIn = Number(web3.utils.fromWei(trade1[0], "ether"));
    const amountOut = Number(web3.utils.fromWei(trade2[1], "ether"));

    return { amountIn, amountOut };
}

module.exports = {
    getTokenAndContract,
    getPairAddress,
    getPairContract,
    getReserves,
    calculatePrice,
    calculateDifference,
    getEstimatedReturn,
};