/// This module allows to manage a Multisig's settings.
/// The action can be to add or remove members, and to change the threshold.

module sui_multisig::config {
    use std::debug::print;
    use std::string::String;
    use sui::clock::Clock;
    use sui_multisig::multisig::Multisig;

    // === Errors ===

    const EThresholdTooHigh: u64 = 0;
    const ENotMember: u64 = 1;
    const EAlreadyMember: u64 = 2;
    const EThresholdNull: u64 = 3;

    // === Structs ===

    // action to be stored in a Proposal
    public struct Manage has store { 
        // if true, add members, if false, remove members
        is_add: bool, 
        // new threshold, has to be <= to new total addresses
        threshold: u64,
        // addresses to add or remove
        addresses: vector<address>
    }

    // === Multisig-only functions ===

    // step 1: propose to modify multisig params
    public fun propose(
        multisig: &mut Multisig, 
        name: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        is_add: bool, // is it to add or remove members
        threshold: u64, // new threshold
        addresses: vector<address>, // addresses to add or remove
        ctx: &mut TxContext
    ) {
        // if threshold null, anyone can propose
        assert!(threshold > 0, EThresholdNull);
        // verify threshold is reachable with new members 
        let new_addr_len = if (is_add) {
            addresses.length() + multisig.members().length()
        } else {
            multisig.members().length() - addresses.length()
        };
        assert!(new_addr_len >= threshold, EThresholdTooHigh);
        // verify proposed addresses match current list
        let mut i = 0;
        while (i < addresses.length()) {
            let addr = addresses[i];
            if (is_add) {
                assert!(!multisig.member_exists(&addr), EAlreadyMember);
            } else {
                assert!(multisig.member_exists(&addr), ENotMember);
            };
            i = i + 1;
        };

        let action = Manage { is_add, threshold, addresses };
        multisig.create_proposal(
            action,
            name,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    
    // step 3: execute the action and modify Multisig object
    public fun execute(
        multisig: &mut Multisig, 
        name: String, 
        clock: &Clock,
        ctx: &mut TxContext
    ) {
        let action = multisig.execute_proposal(name, clock, ctx);
        let Manage { is_add, threshold, addresses } = action;

        multisig.set_threshold(threshold);

        let length = vector::length(&addresses);
        if (length == 0) { 
            return
        } else if (is_add) {
            multisig.add_members(addresses);
        } else {
            multisig.remove_members(addresses);
        };
    }
}
