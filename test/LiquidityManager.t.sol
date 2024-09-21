// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "forge-std/Test.sol";
import "../src/LiquidityManager.sol";

contract LiquidityManagerTest is Test {
    LiquidityManager liquidityManager;
    IUniswapV3PoolState pool;
    IERC20 usdc;
    IERC20 weth;

    address richAccount = 0x40ec5B33f54e0E8A33A975908C5BA1c14e5BbbDf; // Polygon's ERC20 Bridge contract address on Ethereum Mainnet
    address liquidityManagerAddress;

    uint256 mainnetFork;
    string MAINNET_RPC_URL = vm.envString("MAINNET_RPC_URL");

    uint256 amountUSDC = 1000 * 1e6; // 1000 USDC
    uint256 amountWETH = 1 * 1e18;   // 1 WETH

    function setUp() public {
        vm.startPrank(richAccount);

        mainnetFork = vm.createFork(MAINNET_RPC_URL);
        vm.selectFork(mainnetFork);

        liquidityManager = new LiquidityManager();
        liquidityManagerAddress = address(liquidityManager);

        pool = IUniswapV3Pool(0x88e6A0c2dDD26FEEb64F039a2c41296FcB3f5640); // USDC/WETH
        usdc = IERC20(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48); // USDC contract address on Ethereum Mainnet
        weth = IERC20(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2); // WETH contract address on Ethereum Mainnet

        assertGt(usdc.balanceOf(richAccount), amountUSDC, "Not enough USDC");
        assertGt(weth.balanceOf(richAccount), amountWETH, "Not enough WETH");

        usdc.approve(liquidityManagerAddress, type(uint256).max);
        weth.approve(liquidityManagerAddress, type(uint256).max);

        vm.stopPrank();
    }

    function testAddLiquidity() public {
        vm.startPrank(richAccount);

        uint256 usdcBalanceBefore = usdc.balanceOf(richAccount);
        uint256 width = 59; // TODO как решать проблему с округлением тиков???

        bytes32 positionKeyBefore = keccak256(
            abi.encodePacked(
                address(liquidityManager),
                liquidityManager.tickLower(),
                liquidityManager.tickUpper()
            )
        );

        (uint128 liquidityBefore, , , , ) = pool.positions(positionKeyBefore);
        assertEq(liquidityBefore, 0, "Liquidity already exists before adding");

        liquidityManager.addLiquidity(
            address(pool),
            amountUSDC,
            amountWETH,
            width
        );

        uint256 usdcBalanceAfter = usdc.balanceOf(richAccount);

        assertEq(usdcBalanceAfter, usdcBalanceBefore - amountUSDC, "USDC not transferred correctly");

        (uint128 liquidity, , , ,) = pool.positions(
            keccak256(abi.encodePacked(liquidityManagerAddress, liquidityManager.tickLower(), liquidityManager.tickUpper()))
        );
        
        assertGt(liquidity, 0, "Liquidity not added");

        int24 tickLower = liquidityManager.tickLower();
        int24 tickUpper = liquidityManager.tickUpper();

        uint160 sqrtPriceLowerX96 = TickMath.getSqrtRatioAtTick(tickLower);
        uint160 sqrtPriceUpperX96 = TickMath.getSqrtRatioAtTick(tickUpper);

        uint256 lowerPrice = (uint256(sqrtPriceLowerX96) * uint256(sqrtPriceLowerX96)) / (1 << 192);
        uint256 upperPrice = (uint256(sqrtPriceUpperX96) * uint256(sqrtPriceUpperX96)) / (1 << 192);

        uint256 computedWidth = ((upperPrice - lowerPrice) * 10000) / (lowerPrice + upperPrice);

        assertEq(computedWidth, width, "Width does not match expected value");

        vm.stopPrank();
    }
}
