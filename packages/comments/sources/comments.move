module comments::comments {
    use std::string::{String, utf8};
    use sui::clock::{Clock, timestamp_ms};
    use sui::object::{Self, ID, UID};
    use sui::table::{Self, Table};
    use sui::table_vec::{Self, TableVec};
    use sui::transfer::share_object;
    use sui::tx_context::{TxContext, sender};
    #[test_only]
    use sui::clock::create_for_testing;
    #[test_only]
    use sui::clock;

    // errors
    const ECOMMENTS_NOT_EXISTS: u64 = 1;
    const ECOMMENT_OUT_OF_RANGE: u64 = 2;
    const EALREADY_VOTED: u64 = 3;

    const MAX_U64: u64 = 0xffffffffffffffff;

    // comments
    struct Application has key, store {
        id: UID,
        comments: Table<ID, TableVec<Comment>>
    }

    struct Comment has store {
        sender: address,
        content: String,
        create_time: u64,
        up_votes: u64,
        down_votes: u64,
        quote: u64,  // if it's a reply, the index of the comment it replies to, MAX_U64 means not a reply

        // not shown in the UI
        voters: Table<address, bool>,  // prevent double voting, bool means up or down
    }

    public fun create_app(
        ctx: &mut TxContext,
    ) {
        let app = Application {
            id: object::new(ctx),
            comments: table::new(ctx),
        };
        share_object(app)
    }

    public fun comment(
        app: &mut Application,
        id: ID,
        content: vector<u8>,
        quote: u64,
        clock: &Clock,
        ctx: &mut TxContext,
    ) {
        if (!table::contains(&app.comments, id)) {
            let default = table_vec::empty(ctx);
            table::add(&mut app.comments, id, default);
        };
        let comments = table::borrow_mut(&mut app.comments, id);
        let sender = sender(ctx);
        let comment = Comment {
            sender,
            content: utf8(content),
            create_time: timestamp_ms(clock),
            up_votes: 0,
            down_votes: 0,
            quote,
            voters: table::new(ctx),
        };
        table_vec::push_back(comments, comment);
    }

    public fun vote (
        app: &mut Application,
        id: ID,
        comment_index: u64,
        up: bool,
        ctx: &mut TxContext,
    ) {
        let sender = sender(ctx);
        assert!(table::contains(&app.comments, id), ECOMMENTS_NOT_EXISTS);
        let comments = table::borrow_mut(&mut app.comments, id);
        assert!(table_vec::length(comments) > comment_index, ECOMMENT_OUT_OF_RANGE);
        let comment = table_vec::borrow_mut(comments, comment_index);
        assert!(!table::contains(&comment.voters, sender), EALREADY_VOTED);
        table::add(&mut comment.voters, sender, up);
        if (up) {
            comment.up_votes = comment.up_votes + 1
        } else {
            comment.down_votes = comment.down_votes + 1
        }
    }

    #[test]
    fun test_comment() {
        use sui::test_scenario;

        let user = @0x11;

        // create app
        let scenario = test_scenario::begin(user);
        create_app(test_scenario::ctx(&mut scenario));

        test_scenario::next_tx(&mut scenario, user);
        let clock = create_for_testing(test_scenario::ctx(&mut scenario));
        let app = test_scenario::take_shared<Application>(&mut scenario);

        // comment and upvote
        test_scenario::next_tx(&mut scenario, user);
        let id = object::id(&app);
        comment(&mut app, id, b"hello", MAX_U64, &clock, test_scenario::ctx(&mut scenario));
        vote(&mut app, id, 0, true, test_scenario::ctx(&mut scenario));

        // check comment
        test_scenario::next_tx(&mut scenario, user);
        let comments = &app.comments;
        assert!(table::length(comments) == 1, 0);
        let comments = table::borrow(comments, id);
        let comment = table_vec::borrow(comments, 0);
        assert!(comment.up_votes == 1, 0);

        // destroy app
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(app);
        test_scenario::end(scenario);
    }
}
