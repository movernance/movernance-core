#[test_only]
module movernance::movernance_tests {
    use movernance::movernance::{create_space, create_token_gov_proposal, vote_with_token, create_reward, add_reward, claim_reward, init_for_testing, SpaceStore, GovSpace, GovProposal, Reward, get_spaces, vote_with_nfts, create_nft_gov_proposal};
    use std::debug;
    use std::vector;
    use sui::clock::{Self, increment_for_testing, create_for_testing};
    use sui::coin::mint_for_testing;
    use sui::object::{Self, UID};
    use sui::sui::SUI;
    use sui::table;
    use sui::tx_context::TxContext;

    struct TestNFT has key, store {
        id: UID,
    }

    fun mint_test_nfts(num: u64, ctx: &mut TxContext): vector<TestNFT> {
        let nfts = vector::empty<TestNFT>();
        let i = 0;
        while(i < num) {
            vector::push_back(&mut nfts, TestNFT { id: object::new(ctx) });
            i = i + 1;
        };
        nfts
    }

    #[test]
    fun test_token_gov_success() {
        use sui::test_scenario;

        let publisher = @0x11;
        let space_creator = @0x22;
        let proposer = @0x33;
        let voter0 = @0x44;
        let voter1 = @0x55;
        let sponsor = @0x66;

        let scenario = test_scenario::begin(publisher);
        {
            init_for_testing(test_scenario::ctx(&mut scenario));
        };
        test_scenario::next_tx(&mut scenario, space_creator);
        let clock = create_for_testing(test_scenario::ctx(&mut scenario));
        {
            let space_store = test_scenario::take_shared<SpaceStore>(&mut scenario);
            create_space<SUI, SUI>(
                &mut space_store,
                b"space example",
                b"space description",
                b"space url",
                b"space metadata",
                10,
                0,
                test_scenario::ctx(&mut scenario),
            );
            assert!(table::length(get_spaces(&space_store)) == 1, 1);
            test_scenario::return_shared(space_store)
        };
        test_scenario::next_tx(&mut scenario, proposer);
        {
            let space = test_scenario::take_shared<GovSpace<SUI, SUI>>(&mut scenario);
            let propose_coin = mint_for_testing<SUI>(11, test_scenario::ctx(&mut scenario));
            increment_for_testing(&mut clock, 100);
            create_token_gov_proposal<SUI, SUI>(
                &mut space,
                propose_coin,
                b"proposal title",
                b"proposal body",
                0,
                1000,
                10,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(space);
        };
        test_scenario::next_tx(&mut scenario, voter0);
        {
            let proposal = test_scenario::take_shared<GovProposal<SUI, SUI>>(&mut scenario);
            let vote_coin = mint_for_testing<SUI>(6, test_scenario::ctx(&mut scenario));
            increment_for_testing(&mut clock, 100);
            vote_with_token<SUI, SUI>(&mut proposal, vote_coin,  true, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(proposal);
        };
        test_scenario::next_tx(&mut scenario, voter1);
        {
            let proposal = test_scenario::take_shared<GovProposal<SUI, SUI>>(&mut scenario);
            let vote_coin = mint_for_testing<SUI>(5, test_scenario::ctx(&mut scenario));
            vote_with_token<SUI, SUI>(&mut proposal, vote_coin,  false, &clock, test_scenario::ctx(&mut scenario));
            debug::print(&proposal);
            test_scenario::return_shared(proposal);
        };
        // add reward
        test_scenario::next_tx(&mut scenario, sponsor);
        {
            let proposal = test_scenario::take_shared<GovProposal<SUI, SUI>>(&mut scenario);
            let reward_coin = mint_for_testing<SUI>(99, test_scenario::ctx(&mut scenario));
            create_reward<SUI, SUI, SUI>(
                &mut proposal,
                reward_coin,
                true,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(proposal);
        };
        test_scenario::next_tx(&mut scenario, sponsor);
        {
            let proposal = test_scenario::take_shared<GovProposal<SUI, SUI>>(&mut scenario);
            let reward = test_scenario::take_shared<Reward<SUI>>(&mut scenario);
            let reward_coin1 = mint_for_testing<SUI>(100, test_scenario::ctx(&mut scenario));
            add_reward(
                &proposal,
                &mut reward,
                reward_coin1,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            debug::print(&reward);
            test_scenario::return_shared(reward);
            test_scenario::return_shared(proposal);
        };
        test_scenario::next_tx(&mut scenario, voter0);
        // claim reward
        {
            let proposal = test_scenario::take_shared<GovProposal<SUI, SUI>>(&mut scenario);
            let reward = test_scenario::take_shared<Reward<SUI>>(&mut scenario);
            increment_for_testing(&mut clock, 1000);
            claim_reward<SUI, SUI, SUI>(&proposal, &mut reward, &clock, test_scenario::ctx(&mut scenario));
            debug::print(&reward);
            test_scenario::return_shared(reward);
            test_scenario::return_shared(proposal);
        };
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }

    #[test]
    fun test_nft_gov_success() {
        use sui::test_scenario;

        let publisher = @0x11;
        let space_creator = @0x22;
        let proposer = @0x33;
        let voter0 = @0x44;
        let voter1 = @0x55;
        let sponsor = @0x66;

        let scenario = test_scenario::begin(publisher);
        {
            init_for_testing(test_scenario::ctx(&mut scenario));
        };
        test_scenario::next_tx(&mut scenario, space_creator);
        let clock = create_for_testing(test_scenario::ctx(&mut scenario));
        {
            let space_store = test_scenario::take_shared<SpaceStore>(&mut scenario);
            create_space<TestNFT, TestNFT>(
                &mut space_store,
                b"space example",
                b"space description",
                b"space url",
                b"space metadata",
                1,
                1,
                test_scenario::ctx(&mut scenario),
            );
            assert!(table::length(get_spaces(&space_store)) == 1, 1);
            test_scenario::return_shared(space_store)
        };
        test_scenario::next_tx(&mut scenario, proposer);
        {
            let space = test_scenario::take_shared<GovSpace<TestNFT, TestNFT>>(&mut scenario);
            let propose_nfts = mint_test_nfts(11, test_scenario::ctx(&mut scenario));
            increment_for_testing(&mut clock, 100);
            create_nft_gov_proposal<TestNFT, TestNFT>(
                &mut space,
                propose_nfts,
                b"proposal title",
                b"proposal body",
                0,
                1000,
                1,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(space);
        };
        test_scenario::next_tx(&mut scenario, voter0);
        {
            let proposal = test_scenario::take_shared<GovProposal<TestNFT, TestNFT>>(&mut scenario);
            let vote_nfts = mint_test_nfts(6, test_scenario::ctx(&mut scenario));
            increment_for_testing(&mut clock, 100);
            vote_with_nfts<TestNFT, TestNFT>(&mut proposal, vote_nfts,  true, &clock, test_scenario::ctx(&mut scenario));
            test_scenario::return_shared(proposal);
        };
        test_scenario::next_tx(&mut scenario, voter1);
        {
            let proposal = test_scenario::take_shared<GovProposal<TestNFT, TestNFT>>(&mut scenario);
            let vote_nfts = mint_test_nfts(5, test_scenario::ctx(&mut scenario));
            vote_with_nfts<TestNFT, TestNFT>(&mut proposal, vote_nfts,  false, &clock, test_scenario::ctx(&mut scenario));
            debug::print(&proposal);
            test_scenario::return_shared(proposal);
        };
        // add reward
        test_scenario::next_tx(&mut scenario, sponsor);
        {
            let proposal = test_scenario::take_shared<GovProposal<TestNFT, TestNFT>>(&mut scenario);
            let reward_coin = mint_for_testing<SUI>(99, test_scenario::ctx(&mut scenario));
            create_reward<TestNFT, TestNFT, SUI>(
                &mut proposal,
                reward_coin,
                true,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            test_scenario::return_shared(proposal);
        };
        test_scenario::next_tx(&mut scenario, sponsor);
        {
            let proposal = test_scenario::take_shared<GovProposal<TestNFT, TestNFT>>(&mut scenario);
            let reward = test_scenario::take_shared<Reward<SUI>>(&mut scenario);
            let reward_coin1 = mint_for_testing<SUI>(100, test_scenario::ctx(&mut scenario));
            add_reward(
                &proposal,
                &mut reward,
                reward_coin1,
                &clock,
                test_scenario::ctx(&mut scenario),
            );
            debug::print(&reward);
            test_scenario::return_shared(reward);
            test_scenario::return_shared(proposal);
        };
        test_scenario::next_tx(&mut scenario, voter0);
        // claim reward
        {
            let proposal = test_scenario::take_shared<GovProposal<TestNFT, TestNFT>>(&mut scenario);
            let reward = test_scenario::take_shared<Reward<SUI>>(&mut scenario);
            increment_for_testing(&mut clock, 1000);
            claim_reward<TestNFT, TestNFT, SUI>(&proposal, &mut reward, &clock, test_scenario::ctx(&mut scenario));
            debug::print(&reward);
            test_scenario::return_shared(reward);
            test_scenario::return_shared(proposal);
        };
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario);
    }
}
