/// This module allows multisig members to access objects owned by the multisig in a secure way.
/// The objects can be taken only via an Withdraw action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed using an action wrapping the Withdraw action.
/// Caution: borrowed Coins can be emptied, only withdraw the amount you need
/// withdraw and borrow can only be called using an action executed by the multisig owning the objects

module kraken::owned {    
    use sui::transfer::Receiving;
    use kraken::multisig::{Multisig, Auth};

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EReturnAllObjectsBefore: u64 = 1;
    const ERetrieveAllObjectsBefore: u64 = 2;

    // === Structs ===

    // action to be stored in a Proposal
    // guard access to multisig owned objects which can only be received via this action
    public struct Withdraw has store {
        // the owned objects we want to access
        objects: vector<ID>,
    }

    // action to be stored in a Proposal
    // wrapper enforcing accessed objects to be sent back to the multisig
    public struct Borrow has store {
        // sub action retrieving objects
        withdraw: Withdraw,
        // list of objects to put back into the multisig
        to_return: vector<ID>,
    }

    // === Public functions ===

    public fun new_withdraw(objects: vector<ID>): Withdraw {
        Withdraw { objects }
    }

    // [AUTH] issued from Action to prevent unauthorized withdrawals
    public fun withdraw<T: key + store>(
        action: &mut Withdraw,
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        auth: Auth
    ): T {
        multisig.authentify(auth);
        let id = action.objects.pop_back();
        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }

    public fun complete_withdraw(action: Withdraw) {
        let Withdraw { objects } = action;
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();
    }

    public fun new_borrow(objects: vector<ID>): Borrow {
        Borrow {
            withdraw: new_withdraw(objects),
            to_return: objects,
        }
    }

    // [AUTH] via withdraw to prevent unauthorized borrows
    public fun borrow<T: key + store>(
        action: &mut Borrow,
        multisig: &mut Multisig, 
        receiving: Receiving<T>,
        auth: Auth
    ): T {
        action.withdraw.withdraw(multisig, receiving, auth)
    }
    
    public fun put_back<T: key + store>(
        action: &mut Borrow,
        multisig: &Multisig, 
        returned: T, 
    ) {
        let (exists_, index) = action.to_return.index_of(&object::id(&returned));
        assert!(exists_, EWrongObject);
        action.to_return.swap_remove(index);
        transfer::public_transfer(returned, multisig.addr());
    }

    public fun complete_borrow(action: Borrow) {
        let Borrow { withdraw, to_return } = action;
        complete_withdraw(withdraw);
        assert!(to_return.is_empty(), EReturnAllObjectsBefore);
        to_return.destroy_empty();
    }
}

