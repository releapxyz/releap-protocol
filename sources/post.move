module releap_social::post {
    use std::string::{Self, String};
    use std::vector::{Self};
    use std::option::{Self, Option};

    use sui::object::{Self, UID, ID};
    use sui::dynamic_field as df;
    use sui::clock::{Self, Clock};
    use sui::url::{Self, Url};
    use sui::event::{Self};

    use sui::vec_set::{Self, VecSet};

    use sui::tx_context::{TxContext};

    use releap_social::error::{not_owner};

    friend releap_social::profile;
    friend releap_social::releap_social;
   
    struct PostOwnerCap has key, store { 
        id: UID, 
        post: ID,
        seq: u64,
        content: String,
        image_url: Option<Url>,
    }

    struct Post has key, store {
        id: UID,
        seq: u64,
        image_url: Option<Url>,
        content: String,
        created_at: u64,
        profile: ID,
        parent: Option<ID>,
        comment_count: u64,
        like_count: u64,
        author: ID
    }

    struct CreatePostEvent has copy, drop {
        post_id: ID,
        author: ID,
        content: String,
        image_url: Option<Url>,
    }

    struct CreateCommentEvent has copy, drop {
        post_id: ID,
        post_author: ID,
        comment_id: ID,
        comment_author: ID,
        content: String,
        image_url: Option<Url>,
    }

    struct LikePostEvent has copy, drop {
        post_author: ID,
        post_id: ID,
        profile: ID,
        like_count: u64,
    }

    struct UnlikePostEvent has copy, drop {
        post_author: ID,
        post_id: ID,
        profile: ID,
        like_count: u64,
    }

    fun comments_key(): String {
        string::utf8(b"comments")
    }
    
    fun liked_set_key(): String {
        string::utf8(b"liked_set")
    }

    public(friend) fun create_post(profile_id: ID, image_url: String, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext): (Post, PostOwnerCap) {
        let image_url_converted = option::none();
        if (!string::is_empty(&image_url)) {
            image_url_converted = option::some(url::new_unsafe(string::to_ascii(image_url)));
        };
        let post = Post {
            id: object::new(ctx),
            seq: counter,
            image_url: image_url_converted,
            content: content,
            profile: profile_id,
            parent: option::none(),
            created_at: clock::timestamp_ms(clock),
            author: profile_id,
            comment_count: 0,
            like_count: 0
        };

        let post_id = object::id(&post);

        let post_owner_cap = PostOwnerCap {
            id: object::new(ctx),
            seq: counter,
            post: post_id,
            image_url: image_url_converted,
            content: content,
        };

        // init empty comment list
        df::add(&mut post.id, comments_key(), vector::empty<ID>());
        df::add(&mut post.id, liked_set_key(), vec_set::empty<ID>());

        event::emit(CreatePostEvent {
            post_id: post_id,
            content: post.content,
            image_url: post.image_url,
            author: profile_id,
        });

        (post, post_owner_cap)
    }

    public(friend) fun create_comment(post: &mut Post, author_profile_id: ID, content: String, clock: &Clock, counter: u64, ctx: &mut TxContext): (Post, PostOwnerCap) {
        let comment = Post {
            id: object::new(ctx),
            seq: counter,
            image_url: option::none(),
            content: content,
            profile: post.profile,
            parent: option::some(object::id(post)),
            created_at: clock::timestamp_ms(clock),
            author: author_profile_id,
            comment_count: 0,
            like_count: 0
        };

        let comment_id = object::id(&comment);

        let comment_owner_cap = PostOwnerCap {
            id: object::new(ctx),
            seq: counter,
            post: comment_id,
            image_url: option::none(),
            content: content,
        };

        post.comment_count = post.comment_count + 1;
        let comments: &mut vector<ID> = df::borrow_mut(&mut post.id, comments_key());
        vector::push_back(comments, comment_id);

        // init empty comment list
        df::add(&mut comment.id, comments_key(), vector::empty<ID>());
        df::add(&mut comment.id, liked_set_key(), vec_set::empty<ID>());

        event::emit(CreateCommentEvent {
            comment_id: object::id(&comment),
            comment_author: author_profile_id,
            post_id: object::id(post),
            post_author: post.author,
            content: comment.content,
            image_url: post.image_url,
        });

        (comment, comment_owner_cap)
    }

    public(friend) fun like_post(post: &mut Post, profile_id: ID) {
        let liked: &mut VecSet<ID> = df::borrow_mut(&mut post.id, liked_set_key());
        if (!vec_set::contains(liked, &profile_id)) {
            vec_set::insert(liked, profile_id);
            post.like_count = post.like_count + 1;

            event::emit(LikePostEvent {
                post_id: object::id(post),
                post_author: post.author,
                profile: profile_id,
                like_count: post.like_count,
            });
        }
    }

    public(friend) fun unlike_post(post: &mut Post, profile_id: ID) {
        let liked: &mut VecSet<ID> = df::borrow_mut(&mut post.id, liked_set_key());
        if (vec_set::contains(liked, &profile_id)) {
            vec_set::remove(liked, &profile_id);
            post.like_count = post.like_count - 1;

            event::emit(UnlikePostEvent {
                post_id: object::id(post),
                post_author: post.author,
                profile: profile_id,
                like_count: post.like_count,
            });
        }
    }

    public fun get_post_content(post: &Post): String {
        post.content
    }

    public fun get_post_liked_count(post: &Post): u64 {
        post.like_count
    }

    public fun get_post_liked_profile(post: &Post): &VecSet<ID> {
        df::borrow(&post.id, liked_set_key())
    }

    public fun create_display(): (vector<String>, vector<String>) {
        let keys = vector[
            string::utf8(b"name"),
            string::utf8(b"image_url"),
            string::utf8(b"description"),
            string::utf8(b"like_count"),
            string::utf8(b"comments_count"),
        ];

        let values = vector[
            string::utf8(b"Releap Post #{seq}"),
            string::utf8(b"{image_url}"),
            string::utf8(b"{content}"),
            string::utf8(b"{like_count}"),
            string::utf8(b"{comment_count}"),
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
            string::utf8(b"Releap Post #{seq}"),
            string::utf8(b"{image_url}"),
            string::utf8(b"{content}"),
        ];

        (keys, values)
    }

    public fun assert_post_owner(post: &Post, cap: &PostOwnerCap) {
        assert!(object::id(post) == cap.post, not_owner());
    }
}
