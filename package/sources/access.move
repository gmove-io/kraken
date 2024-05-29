/// This module allows multisig members to access objects access by the multisig in a secure way.
/// The objects can be taken only via an Access action.
/// This action can't be proposed directly since it wouldn't make sense to withdraw an object without using it.
/// Objects can be borrowed using an action wrapping the Access action.
/// Caution: borrowed Coins can be emptied, only withdraw the amount you need

module kraken::access {    
    use sui::transfer::Receiving;
    use kraken::multisig::{Multisig, Promise};

    // === Errors ===

    const EWrongObject: u64 = 0;
    const EReturnAllObjectsBefore: u64 = 1;
    const ERetrieveAllObjectsBefore: u64 = 2;

    // === Structs ===

    // action to be stored in a Proposal
    // guard access to multisig owned objects which can only be received via this action
    public struct Access has store {
        // all owned objects we want to access
        objects: vector<ID>,
        // temporary objects to be returned after the action is completed
        temporary: vector<ID>,
    }

    // === Package functions ===

    public fun new(
        objects: vector<ID>,
        temporary: vector<ID>,
    ): Access {
        Access { objects, temporary }
    }

    public fun take<O: key + store>(
        multisig: &mut Multisig,
        promise: &mut Promise,
        receiving: Receiving<O>
    ): O {
        let access = promise.get_access<Access>();
        let (exists_, index) = access.temporary.index_of(&transfer::receiving_object_id(&receiving));
        assert!(exists_, EWrongObject);
        let id = access.temporary.swap_remove(index);

        let received = transfer::public_receive(multisig.uid_mut(), receiving);
        let received_id = object::id(&received);
        assert!(received_id == id, EWrongObject);

        received
    }    
    
    public fun put_back<O: key + store>(
        promise: &mut Promise,
        returning: O, 
    ) {
        let access = promise.get_access<Access>();
        let (exists_, index) = access.temporary.index_of(&object::id(&returning));
        assert!(exists_, EWrongObject);
        access.temporary.swap_remove(index);
        transfer::public_transfer(returning, promise.get_multisig_addr());
    }

    public fun complete(promise: &mut Promise) {
        let access = promise.get_access<Access>();
        let Access { objects, temporary } = access;
        assert!(objects.is_empty(), ERetrieveAllObjectsBefore);
        assert!(temporary.is_empty(), ERetrieveAllObjectsBefore);
        objects.destroy_empty();
        temporary.destroy_empty();
    }
}

