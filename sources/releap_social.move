module releap_social::releap_social {
    use std::string::{String};
    use std::vector::{Self}; 

    use sui::table::{Self, Table}; 
    use sui::object::{Self, UID, ID}; 
    use sui::sui::{SUI}; 
    use sui::coin::{Self, Coin}; 
    use sui::balance::{Self}; 
    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use sui::package::{Self, Publisher};
    use sui::display::{Self};
    use sui::clock::{Clock};

    use releap_social::profile ::{Self, Profile, ProfileOwnerCap};
    use releap_social::post::{Self, Post, PostOwnerCap};
    use releap_social::error::{not_publisher, profile_cap_limit_reached};

    struct Witness has drop {}

    struct RELEAP_SOCIAL has drop {}

    struct Index has key {
        id: UID,
        profiles: Table<String, ID>,
        profile_cap: u64,
        profile_price: u64,
        beneficiary: address
    }

    struct RecentPosts has key {
        id: UID,
        counter: u64,
        posts: vector<ID>
    }

    struct AdminCap has key, store {
        id: UID
    }

    fun init(otw: RELEAP_SOCIAL, ctx: &mut TxContext) {
        let index = Index {
            id: object::new(ctx),
            profiles: table::new<String, ID>(ctx),
            profile_cap: 333,
            profile_price: 1 * 1_000_000_000, // 0.01 SUI
            beneficiary: tx_context::sender(ctx)
        };

        let recent_posts = RecentPosts {
            id: object::new(ctx),
            counter: 0,
            posts: vector::empty()
        };

        transfer::share_object(index);
        transfer::share_object(recent_posts);

        let publisher = package::claim(otw, ctx);

        let (keys, values) = profile::create_display();
        let profile_display = display::new_with_fields<Profile>(
            &publisher, keys, values, ctx
        );

        let (keys, values) = profile::create_cap_display();
        let profile_cap_display = display::new_with_fields<ProfileOwnerCap>(
            &publisher, keys, values, ctx
        );

        let (keys, values) = post::create_display();
        let post_display = display::new_with_fields<Post>(
            &publisher, keys, values, ctx
        );

        let (keys, values) = post::create_cap_display();
        let post_cap_display = display::new_with_fields<PostOwnerCap>(
            &publisher, keys, values, ctx
        );

        display::update_version(&mut profile_display);
        display::update_version(&mut profile_cap_display);
        display::update_version(&mut post_display);
        display::update_version(&mut post_cap_display);

        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(profile_display, tx_context::sender(ctx));
        transfer::public_transfer(profile_cap_display, tx_context::sender(ctx));
        transfer::public_transfer(post_display, tx_context::sender(ctx));
        transfer::public_transfer(post_cap_display, tx_context::sender(ctx));
    }

    public entry fun new_profile(index: &mut Index, name: String, clock: &Clock, wallet: &mut Coin<SUI>,  ctx: &mut TxContext) {
        assert!(table::length<String, ID>(&index.profiles) < index.profile_cap, profile_cap_limit_reached());
        let amount = coin::value(wallet);
        let balance = balance::split(coin::balance_mut(wallet), amount);
        transfer::public_transfer(coin::from_balance<SUI>(balance, ctx), index.beneficiary);

        let (parsed_name, profile, profile_owner_cap) = profile::new(name, clock, ctx);

        table::add(&mut index.profiles, parsed_name, object::id(&profile));

        transfer::public_transfer(profile_owner_cap, tx_context::sender(ctx));
        transfer::public_share_object(profile);
    }

    public entry fun add_wallet_delegation(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, wallet: address) {
        profile::add_wallet_to_delegation_wallets(profile, profile_owner_cap, wallet);       
    }

    public entry fun remove_wallet_delegation(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, wallet: address) {
        profile::remove_wallet_from_delegation_wallets(profile, profile_owner_cap, wallet);
    }

    public entry fun update_profile_description(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, description: String, _ctx: &mut TxContext) {
        profile::update_profile_description(profile, profile_owner_cap, description, _ctx);
    }

    public entry fun update_profile_image(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, image_url: String, _ctx: &mut TxContext) {
        profile::update_profile_image(profile, profile_owner_cap, image_url, _ctx);
    }

    public entry fun update_profile_cover_image(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, cover_url: String, _ctx: &mut TxContext) {
        profile::update_cover_image(profile, profile_owner_cap, cover_url, _ctx);
    }

    public entry fun create_post(profile: &mut Profile, profile_owner_cap: &ProfileOwnerCap, recent_posts: &mut RecentPosts, image_url: String, content: String, clock: &Clock, ctx: &mut TxContext) {
        recent_posts.counter = recent_posts.counter + 1;
        let post_id = profile::create_post(profile, profile_owner_cap, image_url, content, clock, recent_posts.counter, ctx);
        update_recent_post(recent_posts, post_id);
    }

    public entry fun create_post_delegated(profile: &mut Profile, image_url: String, content: String, clock: &Clock, ctx: &mut TxContext) {
        profile::create_post_delegated(profile, image_url, content, clock, 0, ctx);
    }

    public entry fun create_comment(post: &mut Post, author_profile: &Profile, author_profile_owner_cap: &ProfileOwnerCap, recent_posts: &mut RecentPosts,content: String, clock: &Clock, ctx: &mut TxContext) {
        recent_posts.counter = recent_posts.counter + 1;
        profile::create_comment(post, author_profile, author_profile_owner_cap, content, clock, recent_posts.counter, ctx);
    }

    public entry fun create_comment_delegated(post: &mut Post, author_profile: &mut Profile, content: String, clock: &Clock, ctx: &mut TxContext) {
        profile::create_comment_delegated(post, author_profile, content, clock, 0, ctx);
    }

    public entry fun follow(following_profile: &mut Profile, profile: &mut Profile, profile_owner_cap: &ProfileOwnerCap, _ctx: &mut TxContext) {
        profile::profile_follow(following_profile, profile, profile_owner_cap);      
    }

    public entry fun follow_delegated(following_profile: &mut Profile, profile: &mut Profile, ctx: &mut TxContext) {
        profile::profile_follow_delegated(following_profile, profile, ctx);      
    }

    public entry fun unfollow(following_profile: &mut Profile, profile: &mut Profile, profile_owner_cap: &ProfileOwnerCap, _ctx: &mut TxContext) {
        profile::profile_unfollow(following_profile, profile, profile_owner_cap);      
    }

    public entry fun unfollow_delegated(following_profile: &mut Profile, profile: &mut Profile, ctx: &mut TxContext) {
        profile::profile_unfollow_delegated(following_profile, profile, ctx);      
    }

    public entry fun like_post(post: &mut Post, profile: &Profile, profile_owner_cap: &ProfileOwnerCap, ctx: &mut TxContext) {
        profile::like_post(post, profile, profile_owner_cap, ctx);
    }

    public entry fun like_post_delegated(post: &mut Post, profile: &mut Profile, ctx: &mut TxContext) {
        profile::like_post_delegated(post, profile, ctx);
    }

    public entry fun unlike_post(post: &mut Post, profile: &Profile, profile_owner_cap: &ProfileOwnerCap, ctx: &mut TxContext) {
        profile::unlike_post(post, profile, profile_owner_cap, ctx);
    }

    public entry fun unlike_post_delegated(post: &mut Post, profile: &mut Profile, ctx: &mut TxContext) {
        profile::unlike_post_delegated(post, profile, ctx);
    }

    // admin
    public entry fun new_profile_with_admin_cap(index: &mut Index, name: String, clock: &Clock, _admin_cap: &mut AdminCap,  ctx: &mut TxContext) {
        let (parsed_name, profile, profile_owner_cap) = profile::new(name, clock, ctx);

        table::add(&mut index.profiles, parsed_name, object::id(&profile));

        transfer::public_transfer(profile_owner_cap, tx_context::sender(ctx));
        transfer::public_share_object(profile);
    }

    public entry fun new_profile_with_admin_cap_bypass_name_validation(index: &mut Index, name: String, clock: &Clock, _admin_cap: &mut AdminCap,  ctx: &mut TxContext) {
        let (parsed_name, profile, profile_owner_cap) = profile::new_(name, clock, ctx);

        table::add(&mut index.profiles, parsed_name, object::id(&profile));

        transfer::public_transfer(profile_owner_cap, tx_context::sender(ctx));
        transfer::public_share_object(profile);
    }

    public entry fun create_post_with_admin_cap(profile: &mut Profile, _admin_cap: &mut AdminCap, recent_posts: &mut RecentPosts, image_url: String, content: String, clock: &Clock, ctx: &mut TxContext) {
        recent_posts.counter = recent_posts.counter + 1;
        let post_id = profile::create_post_(profile, image_url, content, clock, recent_posts.counter, ctx);
        update_recent_post(recent_posts, post_id);
    }

    public entry fun create_comment_with_admin_cap(post: &mut Post, author_profile: &Profile, _admin_cap: &mut AdminCap, recent_posts: &mut RecentPosts,content: String, clock: &Clock, ctx: &mut TxContext) {
        recent_posts.counter = recent_posts.counter + 1;
        profile::create_comment_(post, author_profile, content, clock, recent_posts.counter, ctx);
    }

    public entry fun follow_with_admin_cap(following_profile: &mut Profile, profile: &mut Profile, _admin_cap: &mut AdminCap, _ctx: &mut TxContext) {
        profile::profile_follow_(following_profile, profile);      
    }

    public entry fun unfollow_with_admin_cap(following_profile: &mut Profile, profile: &mut Profile, _admin_cap: &mut AdminCap, _ctx: &mut TxContext) {
        profile::profile_unfollow_(following_profile, profile);      
    }

    public entry fun like_post_with_admin_cap(post: &mut Post, profile: &Profile, _admin_cap: &mut AdminCap, _ctx: &mut TxContext) {
        post::like_post(post, object::id(profile));
    }

    public entry fun unlike_post_with_admin_cap(post: &mut Post, profile: &Profile, _admin_cap: &mut AdminCap, _ctx: &mut TxContext) {
        post::unlike_post(post, object::id(profile));
    }

    public entry fun aquires_admin_cap(publisher: &mut Publisher, ctx: &mut TxContext) {
        assert!(package::from_package<Profile>(publisher), not_publisher());
        let admin_cap = AdminCap {
            id: object::new(ctx)   
        };
        transfer::transfer(admin_cap, tx_context::sender(ctx));
    }

    public entry fun update_profile_cap_with_admin_cap(index: &mut Index, _admin_cap: &mut AdminCap, new_cap: u64, _ctx: &mut TxContext) {
        index.profile_cap = new_cap;
    }

    public entry fun update_profile_price_with_admin_cap(index: &mut Index, _admin_cap: &mut AdminCap, new_price: u64, _ctx: &mut TxContext) {
        index.profile_price = new_price;
    }

    public entry fun update_beneficiary_with_admin_cap(index: &mut Index, _admin_cap: &mut AdminCap, new_beneficiary: address, _ctx: &mut TxContext) {
        index.beneficiary = new_beneficiary;
    }

    public entry fun set_profile_df_with_admin_cap<T: store + drop>(profile: &mut Profile, key: String, value: T, _admin_cap: &mut AdminCap, _ctx: &mut TxContext) {
        profile::add_profile_df_(profile, key, value);
    }
    
    // old admin with publisher
    public entry fun admin_update_profile_cap(index: &mut Index, publisher: &mut Publisher, new_cap: u64, _ctx: &mut TxContext) {
        assert!(package::from_package<Index>(publisher), not_publisher());
        index.profile_cap = new_cap;
    }

    public entry fun admin_update_profile_price(index: &mut Index, publisher: &mut Publisher, new_price: u64, _ctx: &mut TxContext) {
        assert!(package::from_package<Index>(publisher), not_publisher());
        index.profile_price = new_price;
    }

    public entry fun admin_update_beneficiary(index: &mut Index, publisher: &mut Publisher, new_beneficiary: address, _ctx: &mut TxContext) {
        assert!(package::from_package<Index>(publisher), not_publisher());
        index.beneficiary = new_beneficiary;
    }

    fun update_recent_post(recent_posts: &mut RecentPosts, new_post_id: ID) {
        vector::push_back<ID>(&mut recent_posts.posts, new_post_id);
        if (vector::length<ID>(&recent_posts.posts) > 30) {
            // This is O(n) operation
            vector::remove<ID>(&mut recent_posts.posts, 0);
        }
    }
    // getter
    public fun get_recent_post_ids(recent_posts: &RecentPosts): &vector<ID> {
        &recent_posts.posts
    }

    #[test_only]
    public fun test_init(ctx: &mut TxContext) {
        init(RELEAP_SOCIAL{}, ctx);
    }

    #[test_only]
    public fun get_recent_posts_counter(recent_posts: &RecentPosts): u64 {
        recent_posts.counter
    }

}

#[test_only]
module releap_social::releap_social_test {
    use releap_social::releap_social::{
        Self,
        Index, 
        RecentPosts, 
        AdminCap
    };

    use sui::coin::{Self, Coin};
    use sui::sui::{SUI};
    use sui::pay::{Self};
    use sui::test_scenario::{Self, ctx};
    use sui::package::{Publisher};
    use std::string::{Self};
    use std::vector::{Self};

    use sui::clock::{Self};
    use sui::object::{Self, ID};
    use sui::vec_set::{Self, VecSet};

    use releap_social::profile::{Profile, ProfileOwnerCap, get_profile_description, get_profile_followings_list, get_profile_followers_list, get_profile_followers_count, get_profile_followings_count};
    use releap_social::post::{Post, get_post_liked_count, get_post_liked_profile, get_post_content};

    const ADMIN: address = @0x000000;
    const USER_1: address = @0x000001;
    const USER_2: address = @0x000002;
    const USER_3: address = @0x000003;

    /* profile price is controlled by frontend
    #[test]
    #[expected_failure]
    public fun test_create_profile_with_not_enough_balance() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(5 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }
    */

    #[test]
    #[expected_failure]
    public fun test_profile_cap_limit() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let publisher = test_scenario::take_from_address<Publisher>(
            scenario,
            ADMIN,
        );

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);


        releap_social::admin_update_profile_cap(&mut social_index, &mut publisher, 0, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let wallet = coin::mint_for_testing<SUI>(10 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_to_address(ADMIN, publisher);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_create_post() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let coin_from_admin = test_scenario::take_from_address<Coin<SUI>>(scenario, ADMIN);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        releap_social::create_post(&mut user_1_profile, &user_1_owner_cap, &mut recent_posts, string::utf8(b"post title"), string::utf8(b"post content"), &clock, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let post: Post = test_scenario::take_shared<Post>(scenario);

        assert!(get_post_content(&post) == string::utf8(b"post content"), 1000);
        assert!(vector::contains(releap_social::get_recent_post_ids(&recent_posts), &object::id(&post)), 1000);
        // admin should take the balance
        assert!(coin::value<SUI>(&coin_from_admin) == 1 * 1_000_000_000, 1);

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(post);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        test_scenario::return_to_address(ADMIN, coin_from_admin);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_global_post_counter() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        // 1
        releap_social::create_post(&mut user_1_profile, &user_1_owner_cap, &mut recent_posts, string::utf8(b""), string::utf8(b"post 1"), &clock, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let post_1: Post = test_scenario::take_shared<Post>(scenario);

        releap_social::new_profile(&mut social_index, string::utf8(b"user 2 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_2_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_2_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_2);
        // 2
        releap_social::create_post(&mut user_2_profile, &user_2_owner_cap, &mut recent_posts, string::utf8(b""), string::utf8(b"post 2"), &clock, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let post_2: Post = test_scenario::take_shared<Post>(scenario);
        // 3
        releap_social::create_comment(&mut post_2, &mut user_2_profile, &user_2_owner_cap, &mut recent_posts, string::utf8(b"comment 1"), &clock, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let comment_1: Post = test_scenario::take_shared<Post>(scenario);


        assert!(get_post_content(&post_1) == string::utf8(b"post 1"), 1000);
        assert!(get_post_content(&post_2) == string::utf8(b"post 2"), 1000);
        assert!(get_post_content(&comment_1) == string::utf8(b"comment 1"), 1000);
        assert!(releap_social::get_recent_posts_counter(&recent_posts) == 3u64, 1000);

        assert!(vector::contains(releap_social::get_recent_post_ids(&recent_posts), &object::id(&post_1)), 1000);
        assert!(vector::contains(releap_social::get_recent_post_ids(&recent_posts), &object::id(&post_2)), 1000);

        // comment not store in recent posts index
        assert!(!vector::contains(releap_social::get_recent_post_ids(&recent_posts), &object::id(&comment_1)), 1000);

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(post_1);
        test_scenario::return_shared(post_2);
        test_scenario::return_shared(comment_1);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        test_scenario::return_to_address(USER_2, user_2_owner_cap);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    public fun test_create_post_with_incorrect_cap() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        releap_social::new_profile(&mut social_index, string::utf8(b"user 2 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_2_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_2_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_2);

        releap_social::create_post(&mut user_1_profile, &user_2_owner_cap, &mut recent_posts, string::utf8(b"post title"), string::utf8(b"post content"), &clock, ctx(scenario));

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        test_scenario::return_to_address(USER_2, user_2_owner_cap);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_profile_following() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);

        releap_social::new_profile(&mut social_index, string::utf8(b"user 2 name"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_2_profile = test_scenario::take_shared<Profile>(scenario);
        let user_2_owner_cap = test_scenario::take_from_sender<ProfileOwnerCap>(scenario);

        releap_social::follow(&mut user_1_profile, &mut user_2_profile, &user_2_owner_cap, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let followers_list: &VecSet<ID> = get_profile_followers_list(&user_1_profile);
        let followings_list: &VecSet<ID> = get_profile_followings_list(&user_2_profile);

        assert!(vec_set::contains(followers_list, &object::id(&user_2_profile)), 1000);
        assert!(vec_set::contains(followings_list, &object::id(&user_1_profile)), 1000);
        assert!(vec_set::size(followers_list) == 1, 1000);
        assert!(vec_set::size(followings_list) == 1, 1000);

        assert!(get_profile_followers_count(&user_1_profile) == 1, 1000);
        assert!(get_profile_followings_count(&user_2_profile) == 1, 1000);
        
        releap_social::unfollow(&mut user_1_profile, &mut user_2_profile, &user_2_owner_cap, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);

        assert!(get_profile_followers_count(&user_1_profile) == 0, 1000);
        assert!(get_profile_followings_count(&user_2_profile) == 0, 1000);
        
        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        test_scenario::return_to_address(USER_2, user_2_owner_cap);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    public fun test_duplicated_profile_name() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"profile_1"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);

        releap_social::new_profile(&mut social_index, string::utf8(b"Profile_1"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_2_profile = test_scenario::take_shared<Profile>(scenario);

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_like_post() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"User 1"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_1_profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        releap_social::new_profile(&mut social_index, string::utf8(b"User 2"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_2_profile = test_scenario::take_shared<Profile>(scenario);
        let user_2_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_2);

        releap_social::create_post(&mut user_1_profile, &user_1_owner_cap, &mut recent_posts, string::utf8(b"Post title"), string::utf8(b"Post content"), &clock, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let post: Post = test_scenario::take_shared<Post>(scenario);

        releap_social::like_post(&mut post, &user_2_profile, &user_2_owner_cap, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);

        assert!(get_post_liked_count(&post) == 1, 1000);
        assert!(vec_set::contains(get_post_liked_profile(&post), &object::id(&user_2_profile)), 1000);

        releap_social::unlike_post(&mut post, &user_2_profile, &user_2_owner_cap, ctx(scenario));
        assert!(get_post_liked_count(&post) == 0, 1000);
        assert!(!vec_set::contains(get_post_liked_profile(&post), &object::id(&user_2_profile)), 1000);
        
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        test_scenario::return_to_address(USER_2, user_2_owner_cap);
        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        clock::destroy_for_testing(clock);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        test_scenario::return_shared(post);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_update_profile_description() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"test_user_1"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_1_profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        assert!(get_profile_description(&user_1_profile) == string::utf8(b""), 1000);
        releap_social::update_profile_description(&mut user_1_profile, &mut user_1_owner_cap, string::utf8(b"my description"), ctx(scenario));
        assert!(get_profile_description(&user_1_profile) == string::utf8(b"my description"), 1000);

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    public fun test_update_profile_description_by_incorrect_cap() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"test_user_1"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_1_profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        releap_social::new_profile(&mut social_index, string::utf8(b"User 2"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_2_profile = test_scenario::take_shared<Profile>(scenario);
        let user_2_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_2);

        releap_social::update_profile_description(&mut user_1_profile, &mut user_2_owner_cap, string::utf8(b"my description"), ctx(scenario));

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        test_scenario::return_to_address(USER_2, user_2_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    public fun test_create_post_by_incorrect_cap() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);

        let wallet = coin::mint_for_testing<SUI>(20 * 100_000_000, ctx(scenario));

        releap_social::new_profile(&mut social_index, string::utf8(b"test_user_1"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_2);
        let user_1_profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        releap_social::new_profile(&mut social_index, string::utf8(b"User 2"), &clock, &mut wallet, ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);
        let user_2_profile = test_scenario::take_shared<Profile>(scenario);
        let user_2_owner_cap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_2);

        releap_social::create_post(&mut user_1_profile, &user_2_owner_cap, &mut recent_posts, string::utf8(b"post title"), string::utf8(b"post content"), &clock, ctx(scenario));

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_2_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        test_scenario::return_to_address(USER_2, user_2_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    public fun test_default_admin_cap_with_short_name() {
    let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);
        let publisher = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
        {
            releap_social::aquires_admin_cap(&mut publisher, ctx(scenario));
            test_scenario::next_tx(scenario, ADMIN);
        };
        let admin_cap = test_scenario::take_from_address<AdminCap>(scenario, ADMIN);

        {
            releap_social::new_profile_with_admin_cap(&mut social_index, string::utf8(b"test"), &clock, &mut admin_cap, ctx(scenario));
            test_scenario::next_tx(scenario, ADMIN);
        };

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        test_scenario::return_to_address(ADMIN, publisher);
        test_scenario::return_to_address(ADMIN, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_default_admin_cap() {
    let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);
        let publisher = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
        {
            releap_social::aquires_admin_cap(&mut publisher, ctx(scenario));
            test_scenario::next_tx(scenario, ADMIN);
        };
        let admin_cap = test_scenario::take_from_address<AdminCap>(scenario, ADMIN);

        {
            releap_social::new_profile_with_admin_cap(&mut social_index, string::utf8(b"test1234"), &clock, &mut admin_cap, ctx(scenario));
            test_scenario::next_tx(scenario, ADMIN);
        };

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        test_scenario::return_to_address(ADMIN, publisher);
        test_scenario::return_to_address(ADMIN, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    public fun test_default_admin_cap_with_short_name_and_bypass_validation() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, ADMIN);

        let social_index = test_scenario::take_shared<Index>(scenario);
        let recent_posts = test_scenario::take_shared<RecentPosts>(scenario);
        let publisher = test_scenario::take_from_address<Publisher>(scenario, ADMIN);
        {
            releap_social::aquires_admin_cap(&mut publisher, ctx(scenario));
            test_scenario::next_tx(scenario, ADMIN);
        };
        let admin_cap = test_scenario::take_from_address<AdminCap>(scenario, ADMIN);

        {
            releap_social::new_profile_with_admin_cap_bypass_name_validation(&mut social_index, string::utf8(b"test"), &clock, &mut admin_cap, ctx(scenario));
            test_scenario::next_tx(scenario, ADMIN);
        };

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(recent_posts);
        test_scenario::return_to_address(ADMIN, publisher);
        test_scenario::return_to_address(ADMIN, admin_cap);
        clock::destroy_for_testing(clock);
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_create_post_with_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    fun test_create_post_with_non_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_create_commnet_with_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        let post: Post = test_scenario::take_shared<Post>(scenario);
        {
            releap_social::create_comment_delegated(&mut post, &mut user_1_profile, string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        test_scenario::return_shared(post);
        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_like_with_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        let post: Post = test_scenario::take_shared<Post>(scenario);
        {
            releap_social::like_post_delegated(&mut post, &mut user_1_profile, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        test_scenario::return_shared(post);
        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_unlike_with_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        let post: Post = test_scenario::take_shared<Post>(scenario);
        {
            releap_social::like_post_delegated(&mut post, &mut user_1_profile, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::unlike_post_delegated(&mut post, &mut user_1_profile, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        test_scenario::return_shared(post);
        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);

    }

    #[test]
    fun test_follow_with_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_3);
        };


        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 3 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        let user_3_profile: Profile = test_scenario::take_shared<Profile>(scenario);

        {
            releap_social::follow_delegated(&mut user_3_profile, &mut user_1_profile, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };


        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_3_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    fun test_unfollow_with_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_3);
        };

        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 3 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        let user_3_profile: Profile = test_scenario::take_shared<Profile>(scenario);

        {
            releap_social::follow_delegated(&mut user_3_profile, &mut user_1_profile, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::unfollow_delegated(&mut user_3_profile, &mut user_1_profile, ctx(scenario));
            test_scenario::next_tx(scenario, USER_2);
        };


        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_shared(user_3_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }

    #[test]
    #[expected_failure]
    fun test_remove_wallet_from_delegated_wallet() {
        let scenario_val = test_scenario::begin(ADMIN);
        let scenario = &mut scenario_val;
        let clock = clock::create_for_testing(ctx(scenario));

        releap_social::test_init(ctx(scenario));
        test_scenario::next_tx(scenario, USER_1);

        let social_index = test_scenario::take_shared<Index>(scenario);

        let wallet = coin::mint_for_testing<SUI>(1 * 1_000, ctx(scenario));
        {
            releap_social::new_profile(&mut social_index, string::utf8(b"user 1 name"), &clock, &mut wallet, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        let user_1_profile: Profile = test_scenario::take_shared<Profile>(scenario);
        let user_1_owner_cap: ProfileOwnerCap = test_scenario::take_from_address<ProfileOwnerCap>(scenario, USER_1);

        {
            releap_social::add_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        {
            releap_social::remove_wallet_delegation(&mut user_1_profile, &mut user_1_owner_cap, USER_2);
            test_scenario::next_tx(scenario, USER_2);
        };

        {
            releap_social::create_post_delegated(&mut user_1_profile, string::utf8(b"image_url"), string::utf8(b"content"), &clock, ctx(scenario));
            test_scenario::next_tx(scenario, USER_1);
        };

        test_scenario::return_shared(social_index);
        test_scenario::return_shared(user_1_profile);
        test_scenario::return_to_address(USER_1, user_1_owner_cap);
        clock::destroy_for_testing(clock);
        pay::keep(wallet, ctx(scenario));
        test_scenario::end(scenario_val);
    }
}


