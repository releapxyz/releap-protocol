module releap_social::profile {
    use std::string::{Self, String};
    use std::ascii::{Self};
    use std::vector::{Self};

    use sui::object::{Self, UID, ID};
    use sui::vec_set::{Self, VecSet};
    use sui::dynamic_field as df;
    use sui::url::{Self, Url};
    use sui::event::{Self};

    use sui::tx_context::{Self, TxContext};
    use sui::transfer::{Self};
    use sui::clock::{Self, Clock};

    use releap_social::post::{Self, Post};
    use releap_social::error::{not_owner, profile_name_too_short, unexpected_char_in_profile_name, not_delegated};

    friend releap_social::releap_social;

    struct Profile has key, store {
        id: UID,
        name: String,
        description: String,
        website: Url,
        image_url: Url,
        cover_url: Url,
        followers_count: u64,
        followings_count: u64,
        created_at: u64
    }

    struct ProfileOwnerCap has key, store { 
        id: UID, 
        profile: ID,
        name: String,
        description: String,
        image_url: Url,
    }

    struct CreateProfileEvent has copy, drop {
        profile_id: ID,
        name: String,
    }

    struct FollowEvent has copy, drop {
        follower: ID,
        followee: ID,
        followee_follower_count: u64,
        follower_following_count: u64,
    }

    fun followers_key(): String {
        string::utf8(b"followers")
    }
    fun followings_key(): String {
        string::utf8(b"followings")
    }
    fun delegated_wallets_key(): String {
        string::utf8(b"delegated_wallet")
    }
    fun posts_key(): String {
        string::utf8(b"posts")
    }
    fun profile_cap_key(): String {
        string::utf8(b"profile_cap")
    }

    public fun new(name: String, clock: &Clock, ctx: &mut TxContext): (String, Profile, ProfileOwnerCap) {
        let name_checked = parse_and_verifiy_profile_name(name);
        return new_(name_checked, clock, ctx)
    }

    public fun create_post(profile: &mut Profile, profile_owner_cap: &ProfileOwnerCap, title: String, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext): ID {
        assert_profile_owner(profile, profile_owner_cap);
        return create_post_(profile, title, content, clock, counter, ctx)
    }

    public fun create_post_delegated(profile: &mut Profile, image_url: String, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext): ID {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        return create_post_(profile, image_url, content, clock, counter, ctx)
    }

    public fun create_comment(post: &mut Post, profile: &Profile, profile_owner_cap: &ProfileOwnerCap, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext) {
        assert_profile_owner(profile, profile_owner_cap);
        create_comment_(post, profile, content, clock, counter, ctx);
    }

    public fun create_comment_delegated(post: &mut Post, profile: &mut Profile, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        create_comment_(post, profile, content, clock, counter, ctx);
    }

    public fun profile_follow(following_profile: &mut Profile, profile: &mut Profile, profile_owner_cap: &ProfileOwnerCap) {
        assert_profile_owner(profile, profile_owner_cap);
        profile_follow_(following_profile, profile);
    }

    public fun profile_follow_delegated(following_profile: &mut Profile, profile: &mut Profile, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        profile_follow_(following_profile, profile);
    }

    public fun profile_unfollow(following_profile: &mut Profile, profile: &mut Profile, profile_owner_cap: &ProfileOwnerCap) {
        assert_profile_owner(profile, profile_owner_cap);
        profile_unfollow_(following_profile, profile);
    }

    public fun profile_unfollow_delegated(following_profile: &mut Profile, profile: &mut Profile, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        profile_unfollow_(following_profile, profile);
    }

    public entry fun like_post(post: &mut Post, profile: &Profile, profile_owner_cap: &ProfileOwnerCap, _ctx: &mut TxContext) {
        assert_profile_owner(profile, profile_owner_cap);
        post::like_post(post, object::id(profile));
    }

    public entry fun like_post_delegated(post: &mut Post, profile: &mut Profile, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        post::like_post(post, object::id(profile));
    }

    public entry fun unlike_post(post: &mut Post, profile: &Profile, profile_owner_cap: &ProfileOwnerCap, _ctx: &mut TxContext) {
        assert_profile_owner(profile, profile_owner_cap);
        post::unlike_post(post, object::id(profile));
    }

    public entry fun unlike_post_delegated(post: &mut Post, profile: &mut Profile, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        post::unlike_post(post, object::id(profile));
    }

    public entry fun update_profile_description(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, description: String, _ctx: &mut TxContext) {
        assert_profile_owner(profile, profile_owner_cap);
        profile.description = description;
        profile_owner_cap.description = description;
    }

    public entry fun update_profile_description_delegated(profile: &mut Profile, description: String, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        profile.description = description;
    }

    public entry fun update_profile_image(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, image_url: String, _ctx: &mut TxContext) {
        assert_profile_owner(profile, profile_owner_cap);
        profile.image_url = url::new_unsafe(string::to_ascii(image_url));
        profile_owner_cap.image_url = url::new_unsafe(string::to_ascii(image_url));
    }

    public entry fun update_profile_image_delegated(profile: &mut Profile, image_url: String, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        profile.image_url = url::new_unsafe(string::to_ascii(image_url));
    }

    public entry fun update_cover_image(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, cover_url: String, _ctx: &mut TxContext) {
        assert_profile_owner(profile, profile_owner_cap);
        profile.cover_url = url::new_unsafe(string::to_ascii(cover_url));
    }

    public entry fun update_cover_image_delegated(profile: &mut Profile, cover_url: String, ctx: &mut TxContext) {
        assert_delegated_wallet(profile, &tx_context::sender(ctx));
        profile.cover_url = url::new_unsafe(string::to_ascii(cover_url));
    }

    public fun assert_profile_owner(profile: &Profile, cap: &ProfileOwnerCap) {
        assert!(object::id(profile) == cap.profile, not_owner());
    }

    public fun assert_profile_id_owner(profile_id: ID, cap: &ProfileOwnerCap) {
        assert!(profile_id == cap.profile, not_owner());
    }

    // getter
    public fun get_profile_followers_list(profile: &Profile): &VecSet<ID> {
        df::borrow(&profile.id, followers_key())
    }

    public fun get_profile_followings_list(profile: &Profile): &VecSet<ID> {
        df::borrow(&profile.id, followings_key())
    }

    public fun get_profile_followers_count(profile: &Profile): u64 {
        profile.followers_count
    }

    public fun get_profile_followings_count(profile: &Profile): u64 {
        profile.followings_count
    }

    public fun get_profile_description(profile: &Profile): String {
        profile.description
    }

    public fun get_post(profile: &Profile): &vector<ID> {
        return df::borrow(&profile.id, posts_key())
    }

    // private
    public(friend) fun new_(name: String, clock: &Clock, ctx: &mut TxContext): (String, Profile, ProfileOwnerCap) {
        let profile = Profile {
            name: name,
            description: string::utf8(b""),
            website: url::new_unsafe(ascii::string(b"")),
            image_url: url::new_unsafe(ascii::string(b"")),
            cover_url: url::new_unsafe(ascii::string(b"")),
            id: object::new(ctx),
            followers_count: 0,
            followings_count: 0,
            created_at: clock::timestamp_ms(clock),
        };

        let profile_owner_cap = ProfileOwnerCap {
            id: object::new(ctx),
            profile: object::id(&profile),
            name: name,
            description: string::utf8(b""),
            image_url: url::new_unsafe(ascii::string(b"")),
        };

        df::add(&mut profile.id, followers_key(), vec_set::empty<ID>());
        df::add(&mut profile.id, followings_key(), vec_set::empty<ID>());
        df::add(&mut profile.id, delegated_wallets_key(), vec_set::empty<address>());
        df::add(&mut profile.id, posts_key(), vector::empty<ID>());
        // reference back to the owner_cap
        df::add(&mut profile.id, profile_cap_key(), object::id(&profile_owner_cap));

        add_wallet_to_delegation_wallets_(&mut profile, tx_context::sender(ctx));

        return (name, profile, profile_owner_cap)
    }

    public(friend) fun add_profile_df_<T: store + drop>(profile: &mut Profile, key: String, value: T) {
        if (df::exists_with_type<String, T>(&profile.id, key)) {
            df::remove<String, T>(&mut profile.id, key);
        };
        df::add(&mut profile.id, key, value);
    }

    public(friend) fun create_post_(profile: &mut Profile, image_url: String, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext): ID {
        let (post, post_owner_cap) = post::create_post(object::id(profile), image_url, content, clock, counter, ctx);

        let posts: &mut vector<ID> = df::borrow_mut(&mut profile.id, posts_key());

        let post_id = object::id(&post);
        vector::push_back(posts, post_id);

        transfer::public_transfer(post_owner_cap, tx_context::sender(ctx));
        transfer::public_share_object(post);

        return post_id
    }

    public(friend) fun create_comment_(post: &mut Post, profile: &Profile, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext) {
        let (post, post_owner_cap) = post::create_comment(post, object::id(profile), content, clock, counter, ctx);

        transfer::public_transfer(post_owner_cap, tx_context::sender(ctx));
        transfer::public_share_object(post);
    }

    public(friend) fun profile_follow_(following_profile: &mut Profile, profile: &mut Profile) {
        let followers_list = df::borrow_mut(&mut following_profile.id, followers_key());
        let follower_id = object::id(profile);

        if (!vec_set::contains(followers_list, &follower_id)) {
            vec_set::insert(followers_list, follower_id); 

            let followings_list = df::borrow_mut(&mut profile.id, followings_key());
            vec_set::insert(followings_list, object::id(following_profile));

            following_profile.followers_count = following_profile.followers_count + 1;
            profile.followings_count = profile.followings_count + 1;

            event::emit(FollowEvent {
                followee: object::id(following_profile),
                follower: object::id(profile),
                followee_follower_count: following_profile.followers_count,
                follower_following_count: profile.followings_count
            });
        }
    }

    public(friend) fun profile_unfollow_(following_profile: &mut Profile, profile: &mut Profile) {
        let followers_list = df::borrow_mut(&mut following_profile.id, followers_key());
        let follower_id = object::id(profile);

        if (vec_set::contains(followers_list, &follower_id)) {
            vec_set::remove(followers_list, &object::id(profile));

            let followings_list = df::borrow_mut(&mut profile.id, followings_key());
            vec_set::remove(followings_list, &object::id(following_profile));

            following_profile.followers_count = following_profile.followers_count - 1;
            profile.followings_count = profile.followings_count - 1;
        }
    }

    public fun add_wallet_to_delegation_wallets(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, wallet: address) {
        assert_profile_owner(profile, profile_owner_cap);
        add_wallet_to_delegation_wallets_(profile, wallet);
    }

    public fun remove_wallet_from_delegation_wallets(profile: &mut Profile, profile_owner_cap: &mut ProfileOwnerCap, wallet: address) {
        assert_profile_owner(profile, profile_owner_cap);
        remove_wallet_to_delegation_wallets_(profile, wallet);
    }

    public fun assert_delegated_wallet(profile: &mut Profile, wallet: &address) {
        ensure_delegation_wallets_exist(profile);

        let wallets = df::borrow_mut<String, VecSet<address>>(&mut profile.id, delegated_wallets_key());
        
        assert!(vec_set::contains<address>(wallets, wallet), not_delegated());
    }

    fun ensure_delegation_wallets_exist(profile: &mut Profile) {
        let df_created = df::exists_with_type<String, VecSet<address>>(&mut profile.id, delegated_wallets_key());
        if (!df_created) {
            df::add(&mut profile.id, delegated_wallets_key(), vec_set::empty<address>());
        }
    }

    fun add_wallet_to_delegation_wallets_(profile: &mut Profile, wallet: address) {
        ensure_delegation_wallets_exist(profile);

        let wallets = df::borrow_mut<String, VecSet<address>>(&mut profile.id, delegated_wallets_key());

        let exists = vec_set::contains<address>(wallets, &wallet);

        if (!exists) {
            vec_set::insert(wallets, wallet);
        }
    }

    fun remove_wallet_to_delegation_wallets_(profile: &mut Profile, wallet: address) {
        ensure_delegation_wallets_exist(profile);

        let wallets = df::borrow_mut<String, VecSet<address>>(&mut profile.id, delegated_wallets_key());

        let exists = vec_set::contains<address>(wallets, &wallet);

        if (exists) {
            vec_set::remove(wallets, &wallet);
        }
    }

    fun parse_and_verifiy_profile_name(name: String): String {
        let ascii_name = string::to_ascii(name);
        let length = ascii::length(&ascii_name);
        let bytes = &mut ascii::into_bytes(ascii_name);

        assert!(ascii::all_characters_printable(&ascii_name), unexpected_char_in_profile_name());
        assert!(length >= 5, profile_name_too_short());

        let i = 0;
        while(i < length) {
            let ch: &mut u8 = vector::borrow_mut<u8>(bytes, i);

            if (*ch >= 65 && *ch <= 90) {
                // convert to lower case
                *ch = *ch + 32;
            } else {
                let ch = *ch;
                let valid_ascii = ch >= 97 && ch <= 122 // lower case
                    || ch >= 48 && ch <= 57 // number
                    || ch == 32 // space
                    || ch == 45 // dash
                    || ch == 95; // underscore

                assert!(valid_ascii , unexpected_char_in_profile_name());
            };
            i = i + 1;
        };

        let ascii_name = ascii::string(*bytes);
        string::from_ascii(ascii_name)
    }

    public fun create_display(): (vector<String>, vector<String>) {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"image_url"),
            string::utf8(b"description"),
            string::utf8(b"website"),
            string::utf8(b"followers_count"),
            string::utf8(b"following_count"),
        ];
        let values = vector[
            string::utf8(b"{name}"),
            string::utf8(b"{image_url}"),
            string::utf8(b"{description}"),
            string::utf8(b"{website}"),
            string::utf8(b"{followers_count}"),
            string::utf8(b"{following_count}"),
        ];

        (keys, values)
    }

    public fun create_cap_display(): (vector<String>, vector<String>) {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"image_url"),
            string::utf8(b"description"),
        ];
        let values = vector[
            string::utf8(b"{name}"),
            string::utf8(b"{image_url}"),
            string::utf8(b"{description}"),
        ];

        (keys, values)
    }

    #[test]
    fun test_convert_profile_name_to_lowercase() {
        assert!(parse_and_verifiy_profile_name(string::utf8(b"Test_- abc")) == string::utf8(b"test_- abc"), 1000);
        assert!(parse_and_verifiy_profile_name(string::utf8(b"test_- abc")) == string::utf8(b"test_- abc"), 1000);
    }

    #[test]
    #[expected_failure]
    fun test_short_profile_name() {
        assert!(parse_and_verifiy_profile_name(string::utf8(b"test")) == string::utf8(b"test_abc"), 1000);
    }

    #[test]
    #[expected_failure]
    fun test_invaild_char_1() {
        assert!(parse_and_verifiy_profile_name(string::utf8(b"test##")) == string::utf8(b"test_abc"), 1000);
    }

    #[test]
    #[expected_failure]
    fun test_invaild_char_2() {
        assert!(parse_and_verifiy_profile_name(string::utf8(b"test%%")) == string::utf8(b"test_abc"), 1000);
    }
}
