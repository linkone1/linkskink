const Arbitrage = artifacts.require("Arbitrage");
const MockERC20 = artifacts.require("MockERC20");
const IUniswapV2Router02 = require("@uniswap/v2-periphery/build/IUniswapV2Router02.json");
const config = require("../config.json");

contract("Arbitrage", (accounts) => {
    let arbitrage, weth, dai, sRouter;

    before(async () => {
        arbitrage = await Arbitrage.deployed();
        weth = await MockERC20.deployed(); // Mock WETH
        dai = await MockERC20.deployed(); // Mock DAI
    
        // Use the Sushiswap Router ABI and address from the deployed configuration
        sRouter = new web3.eth.Contract(
            IUniswapV2Router02.abi, // Router ABI
            config.SUSHISWAP.V2_ROUTER_02_ADDRESS // Router address from config
        );
    
        // Reset balances for accounts
        await weth.transfer(accounts[0], web3.utils.toWei("20", "ether")); // Ensure account[0] has WETH
        await dai.transfer(accounts[0], web3.utils.toWei("20", "ether")); // Ensure account[0] has DAI
    
        await weth.transfer(accounts[1], web3.utils.toWei("20", "ether")); // Ensure account[1] has WETH
        await dai.transfer(accounts[1], web3.utils.toWei("20", "ether")); // Ensure account[1] has DAI
    
        // Approve router to use tokens
        await weth.approve(sRouter.options.address, web3.utils.toWei("20", "ether"), { from: accounts[0] });
        await dai.approve(sRouter.options.address, web3.utils.toWei("20", "ether"), { from: accounts[0] });
    
        // Add liquidity to the Sushiswap pool
        try {
            await sRouter.methods
                .addLiquidity(
                    weth.address,
                    dai.address,
                    web3.utils.toWei("10", "ether"), // WETH amount
                    web3.utils.toWei("10", "ether"), // DAI amount
                    web3.utils.toWei("1", "ether"), // Min WETH
                    web3.utils.toWei("1", "ether"), // Min DAI
                    accounts[0], // Recipient
                    Math.floor(Date.now() / 1000) + 60 * 10
                )
                .send({ from: accounts[0], gas: 3000000 });
        } catch (error) {
            console.error("Liquidity addition failed:", error.message);
        }
    });

    it("should retrieve token balances correctly", async () => {
        const balanceWETH = await weth.balanceOf(accounts[1]);
        const balanceDAI = await dai.balanceOf(accounts[1]);

        assert.strictEqual(
            balanceWETH.toString(),
            web3.utils.toWei("20", "ether"),
            "Incorrect WETH balance"
        );
        assert.strictEqual(
            balanceDAI.toString(),
            web3.utils.toWei("20", "ether"),
            "Incorrect DAI balance"
        );
    });

    it("should perform a swap from WETH to DAI", async () => {
        await weth.approve(arbitrage.address, web3.utils.toWei("1", "ether"), { from: accounts[1] });
    
        const initialDAIBalance = await dai.balanceOf(accounts[1]);
    
        try {
            await arbitrage.executeTrade(
                true, // Start on Uniswap
                false, // Do not start on Pancakeswap
                weth.address,
                dai.address,
                web3.utils.toWei("1", "ether"),
                { from: accounts[1] }
            );
        } catch (error) {
            console.error("Swap failed with error:", error.message);
        }
    
        const finalDAIBalance = await dai.balanceOf(accounts[1]);
        console.log("Initial DAI Balance:", initialDAIBalance.toString());
        console.log("Final DAI Balance:", finalDAIBalance.toString());
        assert(finalDAIBalance.gt(initialDAIBalance), "DAI balance did not increase");
    });
    
});
