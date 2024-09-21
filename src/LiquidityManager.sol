// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import '@uniswap/v3-core/contracts/interfaces/IUniswapV3Pool.sol';
import '@uniswap/v3-core/contracts/interfaces/callback/IUniswapV3MintCallback.sol';
import '@uniswap/v3-core/contracts/libraries/TickMath.sol';
import '@uniswap/v3-periphery/contracts/libraries/LiquidityAmounts.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import {console} from "forge-std/console.sol";

contract LiquidityManager is IUniswapV3MintCallback {
    using SafeERC20 for IERC20;

    struct MintCallbackData {
        address payer;
        address token0;
        address token1;
    }

    int24 public tickLower;
    int24 public tickUpper;

    function addLiquidity(
        address poolAddress,
        uint256 amount0Desired,
        uint256 amount1Desired,
        uint256 width
    ) external {
        require(amount0Desired > 0 || amount1Desired > 0, "Liquidity amounts cannot be zero");
        require(width > 0, "Width cannot be zero");

        IUniswapV3Pool pool = IUniswapV3Pool(poolAddress);

        (uint160 sqrtPriceX96, , , , , , ) = pool.slot0();

        int24 tickSpacing = pool.tickSpacing();

        uint256 delta = width * 1e6 / 10000; 

        uint256 currentPrice = uint256(sqrtPriceX96) * uint256(sqrtPriceX96) / (1 << 192);

        uint256 upperPrice = currentPrice * (1e6 + delta) / 1e6;
        uint256 lowerPrice = currentPrice * (1e6 - delta) / 1e6;

        uint160 sqrtPriceUpperX96 = uint160(sqrt(upperPrice) * (1 << 96));
        uint160 sqrtPriceLowerX96 = uint160(sqrt(lowerPrice) * (1 << 96));

        int24 newTickLower = TickMath.getTickAtSqrtRatio(sqrtPriceLowerX96);
        int24 newTickUpper = TickMath.getTickAtSqrtRatio(sqrtPriceUpperX96);

        tickLower = (newTickLower / tickSpacing) * tickSpacing;
        tickUpper = (newTickUpper / tickSpacing) * tickSpacing;

        MintCallbackData memory data = MintCallbackData({
            payer: msg.sender,
            token0: pool.token0(),
            token1: pool.token1()
        });

        uint128 liquidity = LiquidityAmounts.getLiquidityForAmounts(
            sqrtPriceX96,
            TickMath.getSqrtRatioAtTick(tickLower),
            TickMath.getSqrtRatioAtTick(tickUpper),
            amount0Desired,
            amount1Desired
        );

        pool.mint(
            address(this),
            tickLower,
            tickUpper,
            liquidity,
            abi.encode(data)
        );
    }

    function uniswapV3MintCallback(
        uint256 amount0Owed,
        uint256 amount1Owed,
        bytes calldata data
    ) external override {
        MintCallbackData memory decoded = abi.decode(data, (MintCallbackData));

        require(
            msg.sender == address(IUniswapV3Pool(msg.sender)),
            "Callback caller is not the pool"
        );

        if (amount0Owed > 0) {
            IERC20(decoded.token0).safeTransferFrom(decoded.payer, msg.sender, amount0Owed);
        }
        if (amount1Owed > 0) {
            IERC20(decoded.token1).safeTransferFrom(decoded.payer, msg.sender, amount1Owed);
        }
    }

    function sqrt(uint y) internal pure returns (uint z) {
        if (y > 3) {
            z = y;
            uint x = y / 2 + 1;
            while (x < z) {
                z = x;
                x = (y / x + x) / 2;
            }
        } else if (y != 0) {
            z = 1;
        }
    }
}
