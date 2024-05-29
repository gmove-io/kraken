/// This module allows to propose a MoveCall action to be executed by a Multisig.
/// The MoveCall action is unwrapped from an approved proposal 
/// and its digest is verified against the actual transaction (digest) 
/// the proposal can request to borrow or withdraw some objects from the Multisig's account in the PTB
/// allowing to get a Cap to call the proposed function.

module kraken::move_call {
    use std::string::String;
    use kraken::multisig::{Multisig, Action};
    use kraken::access::{Self, Withdraw, Borrow};

    // === Error ===

    const EDigestDoesntMatch: u64 = 0;

    // === Structs ===

    // action to be held in a Proposal
    public struct MoveCall has store {
        // digest of the tx we want to execute
        digest: vector<u8>,
        // sub action requesting to access access objects (such as a Coin)
        withdraw: Withdraw,
        // sub action requesting to borrow access objects (such as a Cap)
        borrow: Borrow,
    }

    // === Multisig functions ===

    // step 1: propose a MoveCall by passing the digest of the tx
    public fun propose_move_call(
        multisig: &mut Multisig, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        to_borrow: vector<ID>,
        to_withdraw: vector<ID>,
        ctx: &mut TxContext
    ) {
        let withdraw = access::new_withdraw(to_withdraw);
        let borrow = access::new_borrow(to_borrow);
        let action = MoveCall { digest, withdraw, borrow };

        multisig.create_proposal(
            action,
            key,
            execution_time,
            expiration_epoch,
            description,
            ctx
        );
    }

    // step 2: multiple members have to approve the proposal (multisig::approve_proposal)
    // step 3: execute the proposal and return the action (multisig::execute_proposal)

    // step 4: destroy MoveCall if digest match and return Withdraw
    public fun execute_move_call(action: Action<MoveCall>, ctx: &TxContext): (Withdraw, Borrow) {
        let MoveCall { digest, withdraw, borrow } = action.unpack_action();
        assert!(digest == ctx.digest(), EDigestDoesntMatch);
        
        (withdraw, borrow)
    }    

    // step 5: borrow or withdraw the objects from access (get a Cap to call another function)
    // step 6: destroy Withdraw in access
}

