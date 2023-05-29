module movernance::movernance {
    use std::string::{String, utf8};
    use std::vector;
    use sui::balance::{Self, Balance};
    use sui::clock::{Clock, timestamp_ms};
    use sui::coin::{Self, Coin};
    use sui::event;
    use sui::object::{Self, ID, UID};
    use sui::table::{Self, Table};
    use sui::transfer::{Self, public_transfer};
    use sui::tx_context::{Self, TxContext, sender};

    // errors
    const EEND_TIME_TOO_EARLY: u64 = 1;
    const EINEFFICIENT_PROPOSE_COIN: u64 = 2;
    const EVOTING_PERIOD_OVER: u64 = 3;
    const EVOTING_PERIOD_NOT_OVER: u64 = 4;
    const EREWARD_NOT_MATCH: u64 = 5;
    const EINVALID_CLAIM_REWARD_STATUS: u64 = 6;
    const EINVALID_CLAIM_REWARD_AMOUNT: u64 = 7;
    const EALREADY_CLAIMED: u64 = 8;
    const EINVALID_VALUE: u64 = 9;
    const EINSUFFICIENT_COINS: u64 = 10;
    const ESPACE_NAME_CONFLICT: u64 = 11;
    const EINVALID_START_TIME: u64 = 12;
    const EVOTING_NOT_STARTED: u64 = 13;
    const ENOT_AUTHORIZED: u64 = 14;
    const EINVALID_GOV_TYPE: u64 = 15;
    const EINEFFICIENT_PROPOSE_NFTS: u64 = 16;

    // proposal status
    const STATUS_VOTING: u8 = 0;
    const STATUS_NOT_ENOUGH_VOTES: u8 = 1;
    const STATUS_SUCCESS: u8 = 2;
    const STATUS_FAIL: u8 = 3;
    const STATUS_NOT_STARTED: u8 = 4;

    // governance type
    const GOV_TYPE_COIN: u8 = 0;
    const GOV_TYPE_NFT: u8 = 1;

    // structs
    struct SpaceStore has key, store {
        id: UID,
        /// space name indexer
        spaces: Table<String, ID>,
    }

    // P: Proposal Token / NFT
    // T: Voting Token / NFT
    struct GovSpace<phantom P, phantom T> has key, store {
        id: UID,
        gov_type: u8,   // gov type
        name: String,
        description: String,
        url: String,      // avata url
        metadata: String, // json format string, including website, twitter, discord, etc.
        admin: address,
        propose_threshold: u64, // the threshold of coin<P> to propose
        proposals: vector<ID>,
    }

    struct GovProposal<phantom P, phantom T> has key, store {
        id: UID,
        space_id: ID,
        gov_type: u8,   // gov type
        title: String,
        body: String, // ipfs link of body
        creator: address,
        start_time: u64,
        end_time: u64,
        min_vote_threshold: u64, // the minimum number of votes to pass
        yes_votes: u64,
        no_votes: u64,
        yes_voters: Table<address, u64>,
        no_voters: Table<address, u64>,
        rewards: vector<ID>,
    }

    struct VoteEvent has copy, drop {
        proposal_id: ID,
        voter: address,
        choice: bool,
        amount: u64,
    }

    struct TokenVote<phantom T> has key, store {
        id: UID,
        voter: address,
        choice: bool,
        proposal_id: ID,
        token: Balance<T>,
    }

    struct NftVote<T> has key, store {
        id: UID,
        voter: address,
        choice: bool,
        proposal_id: ID,
        nfts: vector<T>,
    }

    struct Reward<phantom T> has key, store {
        id: UID,
        proposal_id: ID,
        choice: bool,
        balance: Balance<T>,
        sponsers: Table<address, u64>,
        claimed_addresses: Table<address, bool>,
    }

    fun init(ctx: &mut TxContext) {
        create_space_store(ctx)
    }

    #[test_only]
    public fun init_for_testing(ctx: &mut TxContext) {
        init(ctx)
    }

    fun create_space_store(ctx: &mut TxContext) {
        let store = SpaceStore {
            id: object::new(ctx),
            spaces: table::new(ctx),
        };
        transfer::share_object(store)
    }

    public entry fun create_space<P, T>(
        space_store: &mut SpaceStore,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        metadata: vector<u8>,
        propose_threshold: u64,
        gov_type: u8,
        ctx: &mut TxContext,
    ) {
        let name = utf8(name);
        assert!(!table::contains(&space_store.spaces, name), ESPACE_NAME_CONFLICT);
        assert!(gov_type == GOV_TYPE_COIN || gov_type == GOV_TYPE_NFT, EINVALID_GOV_TYPE);
        let space = GovSpace<P, T> {
            id: object::new(ctx),
            name,
            description: utf8(description),
            url: utf8(url),
            metadata: utf8(metadata),
            admin: tx_context::sender(ctx),
            propose_threshold,
            proposals: vector::empty(),
            gov_type,
        };
        table::add(&mut space_store.spaces, space.name, object::uid_to_inner(&space.id));
        transfer::share_object(space)
    }

    public entry fun edit_gov_space_meta<P, T>(
        space: &mut GovSpace<P, T>,
        name: vector<u8>,
        description: vector<u8>,
        url: vector<u8>,
        metadata: vector<u8>,
        propose_threshold: u64,
        ctx: &mut TxContext,
    ) {
        assert!(tx_context::sender(ctx) == space.admin, ENOT_AUTHORIZED);
        space.name = utf8(name);
        space.description = utf8(description);
        space.url = utf8(url);
        space.metadata = utf8(metadata);
        space.propose_threshold = propose_threshold;
    }

    fun inner_create_proposal<P, T>(
        space: &mut GovSpace<P, T>,
        title: vector<u8>,
        body: vector<u8>,
        start_time: u64,
        end_time: u64,
        min_vote_threshold: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        let now = timestamp_ms(clock);
        assert!(now < end_time, EEND_TIME_TOO_EARLY);
        assert!(start_time < end_time, EINVALID_START_TIME);
        let proposal = GovProposal<P, T> {
            id: object::new(ctx),
            space_id: object::uid_to_inner(&space.id),
            gov_type: space.gov_type,
            title: utf8(title),
            body: utf8(body),
            creator: tx_context::sender(ctx),
            start_time,
            end_time,
            min_vote_threshold,
            yes_votes: 0,
            no_votes: 0,
            yes_voters: table::new(ctx),
            no_voters: table::new(ctx),
            rewards: vector::empty(),
        };
        vector::push_back(&mut space.proposals, object::uid_to_inner(&proposal.id));
        transfer::share_object(proposal)
    }

    public entry fun create_token_gov_proposal<P, T>(
        space: &mut GovSpace<P, T>,
        propose_coin: Coin<P>,
        title: vector<u8>,
        body: vector<u8>,
        start_time: u64,
        end_time: u64,
        min_vote_threshold: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(space.gov_type == GOV_TYPE_COIN, EINVALID_GOV_TYPE);
        assert!(coin::value(&propose_coin) >= space.propose_threshold, EINEFFICIENT_PROPOSE_COIN);
        public_transfer(propose_coin, sender(ctx));
        inner_create_proposal(space, title, body, start_time, end_time, min_vote_threshold, clock, ctx)
    }

    public entry fun create_nft_gov_proposal<P: key + store, T>(
        space: &mut GovSpace<P, T>,
        propose_nfts: vector<P>,
        title: vector<u8>,
        body: vector<u8>,
        start_time: u64,
        end_time: u64,
        min_vote_threshold: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(space.gov_type == GOV_TYPE_NFT, EINVALID_GOV_TYPE);
        assert!(vector::length(&propose_nfts) >= space.propose_threshold, EINEFFICIENT_PROPOSE_NFTS);
        transfer_nfts(propose_nfts, sender(ctx));
        inner_create_proposal(space, title, body, start_time, end_time, min_vote_threshold, clock, ctx)
    }

    public fun transfer_nfts<T: key + store>(nfts: vector<T>, receiver: address): u64 {
        let propose_nfts_length = vector::length(&nfts);
        let i = 0;
        while(i < propose_nfts_length) {
            let nft = vector::pop_back(&mut nfts);
            public_transfer(nft, receiver);
            i = i + 1;
        };
        vector::destroy_empty(nfts);
        return propose_nfts_length
    }

    fun is_voting_period_over<P, T>(proposal: &GovProposal<P, T>, clock: &Clock): bool {
        timestamp_ms(clock) > proposal.end_time
    }

    public fun get_proposal_status<P, T>(
        proposal: &GovProposal<P, T>,
        clock: &Clock
    ): u8 {
        if(timestamp_ms(clock) < proposal.start_time) {
            return STATUS_NOT_STARTED
        };
        if (!is_voting_period_over(proposal, clock)) {
            return STATUS_VOTING
        };
        if (proposal.yes_votes + proposal.no_votes < proposal.min_vote_threshold) {
            return STATUS_NOT_ENOUGH_VOTES
        };
        if (proposal.yes_votes > proposal.no_votes) {
            STATUS_SUCCESS
        } else {
            STATUS_FAIL
        }
    }

    public entry fun vote_with_token<P, T>(
        proposal: &mut GovProposal<P, T>,
        coin: Coin<T>,
        choice: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(timestamp_ms(clock) >= proposal.start_time, EVOTING_NOT_STARTED);
        assert!(!is_voting_period_over(proposal, clock), EVOTING_PERIOD_OVER);
        let value = coin::value(&coin);
        assert!(value > 0, EINVALID_VALUE);
        let balance = coin::into_balance(coin);
        let voter = tx_context::sender(ctx);
        let vote = TokenVote<T> {
            id: object::new(ctx),
            voter,
            choice,
            proposal_id: object::uid_to_inner(&proposal.id),
            token: balance,
        };
        if (choice) {
            proposal.yes_votes = proposal.yes_votes + value;
            add_vote_in_map(&mut proposal.yes_voters, voter, value);
        } else {
            proposal.no_votes = proposal.no_votes + value;
            add_vote_in_map(&mut proposal.no_voters, voter, value);
        };
        transfer::transfer(vote, voter);
        event::emit(VoteEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            voter: tx_context::sender(ctx),
            choice: true,
            amount: value,
        })
    }

    public entry fun vote_with_nfts<P, T: key + store>(
        proposal: &mut GovProposal<P, T>,
        nfts: vector<T>,
        choice: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(timestamp_ms(clock) >= proposal.start_time, EVOTING_NOT_STARTED);
        assert!(!is_voting_period_over(proposal, clock), EVOTING_PERIOD_OVER);
        let value = vector::length(&nfts);
        assert!(value > 0, EINVALID_VALUE);
        let voter = tx_context::sender(ctx);
        let vote = NftVote<T> {
            id: object::new(ctx),
            voter,
            choice,
            proposal_id: object::uid_to_inner(&proposal.id),
            nfts,
        };
        if (choice) {
            proposal.yes_votes = proposal.yes_votes + value;
            add_vote_in_map(&mut proposal.yes_voters, voter, value);
        } else {
            proposal.no_votes = proposal.no_votes + value;
            add_vote_in_map(&mut proposal.no_voters, voter, value);
        };
        transfer::transfer(vote, voter);
        event::emit(VoteEvent {
            proposal_id: object::uid_to_inner(&proposal.id),
            voter: tx_context::sender(ctx),
            choice: true,
            amount: value,
        })
    }

    fun add_vote_in_map(map: &mut Table<address, u64>, voter: address, vote_num: u64) {
        if (table::contains(map, voter)) {
            let v = table::borrow_mut(map, voter);
            *v = *v + vote_num;
        } else {
            table::add(map, voter, vote_num);
        }
    }

    fun get_with_default(map: &Table<address, u64>, key: address, default: u64): u64 {
        if (table::contains(map, key)) {
            *table::borrow(map, key)
        } else {
            default
        }
    }

    public entry fun withdraw_vote_token<P, T>(
        proposal: &GovProposal<P, T>,
        vote: TokenVote<T>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(is_voting_period_over(proposal, clock), EVOTING_PERIOD_NOT_OVER);
        let TokenVote { id, token, choice: _, voter, proposal_id: _ } = vote;
        let coin = coin::from_balance(token, ctx);
        transfer::public_transfer(coin, voter);
        object::delete(id);
    }

    public entry fun withdraw_vote_nfts<P, T: key + store>(
        proposal: &GovProposal<P, T>,
        vote: NftVote<T>,
        clock: &Clock,
        _ctx: &mut TxContext,
    ) {
        assert!(is_voting_period_over(proposal, clock), EVOTING_PERIOD_NOT_OVER);
        let NftVote { id, nfts, choice: _, voter, proposal_id: _ } = vote;
        transfer_nfts(nfts, voter);
        object::delete(id);
    }

    public entry fun create_reward<P, T, R>(
        proposal: &mut GovProposal<P, T>,
        coin: Coin<R>,
        choice: bool,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!is_voting_period_over(proposal, clock), EVOTING_PERIOD_OVER);
        let value = coin::value(&coin);
        assert!(value > 0, EINVALID_VALUE);
        let balance = coin::into_balance(coin);
        let sponsers = table::new(ctx);
        table::add(&mut sponsers, tx_context::sender(ctx), value);
        let reward = Reward<R> {
            id: object::new(ctx),
            choice,
            proposal_id: object::uid_to_inner(&proposal.id),
            balance,
            sponsers,
            claimed_addresses: table::new(ctx),
        };
        vector::push_back(&mut proposal.rewards, object::uid_to_inner(&reward.id));
        transfer::share_object(reward);
    }

    public entry fun add_reward<P, T, R>(
        proposal: &GovProposal<P, T>,
        reward: &mut Reward<R>,
        coin: Coin<R>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(!is_voting_period_over(proposal, clock), EVOTING_PERIOD_OVER);
        assert!(reward.proposal_id == object::uid_to_inner(&proposal.id), EREWARD_NOT_MATCH);
        let value = coin::value(&coin);
        assert!(value > 0, EINVALID_VALUE);
        let balance = coin::into_balance(coin);
        let sender = tx_context::sender(ctx);
        if (table::contains(&reward.sponsers, sender)) {
            let v = table::borrow_mut(&mut reward.sponsers, sender);
            *v = *v + value;
        } else {
            table::add(&mut reward.sponsers, sender, value);
        };
        balance::join(&mut reward.balance, balance);
    }

    // if reward condition is met, reward will be sent to the voters
    // if not, the reward will be sent back to the sponsors
    public entry fun claim_reward<P, T, R>(
        proposal: &GovProposal<P, T>,
        reward: &mut Reward<R>,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        assert!(is_voting_period_over(proposal, clock), EVOTING_PERIOD_NOT_OVER);
        assert!(reward.proposal_id == object::uid_to_inner(&proposal.id), EREWARD_NOT_MATCH);
        let sender = tx_context::sender(ctx);
        assert!(!table::contains(&reward.claimed_addresses, sender), EALREADY_CLAIMED);
        let status = get_proposal_status(proposal, clock);
        let transfer_num: u64;
        let reward_value = balance::value(&reward.balance);
        if (status == STATUS_NOT_ENOUGH_VOTES) {
            // refund to the sponsors
            transfer_num = get_with_default(&reward.sponsers, sender, 0);
        } else if (status == STATUS_SUCCESS && reward.choice) {
            // reward to the yes voters
            transfer_num = get_with_default(&proposal.yes_voters, sender, 0) * reward_value / proposal.yes_votes;

        } else if (status == STATUS_FAIL && !reward.choice) {
            // reward to the no voters
            transfer_num = get_with_default(&proposal.no_voters, sender, 0) * reward_value / proposal.no_votes;
        } else {
            // invalid status
            abort EINVALID_CLAIM_REWARD_STATUS
        };
        assert!(transfer_num > 0, EINVALID_CLAIM_REWARD_AMOUNT);
        let transfer_coin = coin::from_balance(balance::split(&mut reward.balance, transfer_num), ctx);
        transfer::public_transfer(transfer_coin, sender);
        table::add(&mut reward.claimed_addresses, sender, true);
    }

    public fun get_spaces(
        space_store: &SpaceStore,
    ): &Table<String, ID> {
        &space_store.spaces
    }
}
