module releap_social::error {
    const ERR_BASE: u64 = 0x72656c65617000;

    public fun not_owner(): u64 {
        return ERR_BASE + 100
    }

    public fun profile_name_too_short(): u64 {
        return ERR_BASE + 101
    }

    public fun unexpected_char_in_profile_name(): u64 {
        return ERR_BASE + 102
    }

    public fun not_publisher(): u64 {
        return ERR_BASE + 103
    }

    public fun not_enough_balance(): u64 {
        return ERR_BASE + 104
    }

    public fun profile_cap_limit_reached(): u64 {
        return ERR_BASE + 105
    }

    public fun not_delegated(): u64 {
        return ERR_BASE + 106
    }
}
