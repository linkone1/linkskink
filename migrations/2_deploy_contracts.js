const Arbitrage = artifacts.require("Arbitrage");
const MockERC20 = artifacts.require("MockERC20");
const config = require("../config.json");

module.exports = async function (deployer, network, accounts) {
    if (network === "development") {
        // Deploy mock tokens
        await deployer.deploy(MockERC20, "Mock WETH", "WETH", web3.utils.toWei("1000", "ether"));
        const mockWETH = await MockERC20.deployed();

        await deployer.deploy(MockERC20, "Mock DAI", "DAI", web3.utils.toWei("1000", "ether"));
        const mockDAI = await MockERC20.deployed();

        // Deploy Arbitrage contract
        await deployer.deploy(
            Arbitrage,
            config.SUSHISWAP.V2_ROUTER_02_ADDRESS,
            config.UNISWAP.V2_ROUTER_02_ADDRESS,
            config.PANCAKESWAP.V2_ROUTER_02_ADDRESS
        );

        const arbitrage = await Arbitrage.deployed();

        // Register tokens
        await arbitrage.registerTokens(mockWETH.address, 1, { from: accounts[0] });
        await arbitrage.registerTokens(mockDAI.address, 2, { from: accounts[0] });

        console.log("Mock WETH deployed at:", mockWETH.address);
        console.log("Mock DAI deployed at:", mockDAI.address);
        console.log("Arbitrage contract deployed at:", arbitrage.address);
    }
};
