# System

A small CDP-style money market and a staking rewards program. Everything here is deployed;
`PriceOracle` is fed from an off-chain job.

## PriceOracle

One collateral asset. The price is USD per ETH scaled by 1e18. The protocol admin updates it
when the off-chain feed moves.

## LendingPool

- Users deposit ETH as collateral (`depositCollateral`).
- Users borrow ETH up to 50% of their collateral value (`borrow`). The pool assumes it holds
  enough liquidity; deposits from other users are the source of borrows.
- Positions below the 50% maintenance threshold are meant to be liquidatable (`liquidate`).
  The liquidator receives the position's collateral.

## Rewards

- Users stake ERC-20 tokens (`stake`) and can unstake at any time (`unstake`).
- Every staked token earns `REWARD_PER_TOKEN` (0.3 tokens, 1e18 scale) over the program.
- `earned(user)` is the total reward for a user's current stake; `claim` pays out the
  unclaimed difference.
