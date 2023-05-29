module movernance::test_nft {
    use sui::object::{Self, UID};
    use sui::tx_context::{TxContext, sender};
    use std::vector;
    use sui::transfer::public_transfer;

    struct TestNFT has key, store {
        id: UID,
    }

    public fun claim(
        num: u64,
        ctx: &mut TxContext,
    ): vector<TestNFT> {
        let i = 0;
        let nfts = vector::empty();
        while(i < num) {
            vector::push_back(&mut nfts, TestNFT { id: object::new(ctx) });
            i = i + 1;
        };
        nfts
    }

    public fun claim_and_transfer(
        num: u64,
        ctx: &mut TxContext,
    ) {
        let sender = sender(ctx);
        let i = 0;
        while(i < num) {
            let nft = TestNFT { id: object::new(ctx) };
            public_transfer(nft, sender);
            i = i + 1;
        };
    }
}
