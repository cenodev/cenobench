# System

A small fixed-price marketplace for ERC-20 items, plus signed offers and a fee mechanism.

## Marketplace

- The protocol fee is in basis points of a sale price (`protocolFeeBps`, default 250 = 2.5%).
- The admin updates the fee when the business terms change (`setProtocolFeeBps`).
- `feeFor(price)` is used by the sale contracts to compute the protocol's cut.

## BuyNow

- Sellers list an ERC-20 item with a fixed price (`list`).
- A buyer pays with ETH (`buy`). The listing is consumed by the first successful purchase.
- The buyer pays exactly the listing price. Any excess ETH sent must be returned to the buyer
  in the same transaction; the contract is not supposed to custody buyer funds.

## Offers

- A maker signs an offer to buy an item at a price (`Offer` + `fillOffer`).
- The signed offer is filled by the item's holder: the item goes to the maker and the price
  goes to the filler.
- An offer is single-use: once filled it must never be fillable again.
