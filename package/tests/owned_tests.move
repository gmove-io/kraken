#[test_only]
module kraken::owned_tests{    
    use sui::test_utils::{assert_eq, destroy};
    use sui::test_scenario::{receiving_ticket_by_id, take_from_address_by_id};

    use kraken::access;
    use kraken::test_utils::start_world;

    const OWNER: address = @0xBABE;

    public struct Object has key, store { id: UID }

    #[test]
    fun test_withdraw_end_to_end() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.scenario().next_tx(OWNER);

        let mut withdraw = access::new_withdraw(vector[id1, id2]);

        let object2 = withdraw.withdraw<Object>(world.multisig(), receiving_ticket_by_id(id2));
        let object1 = withdraw.withdraw<Object>(world.multisig(), receiving_ticket_by_id(id1));

        assert_eq(object2.id.to_inner(), id2);
        assert_eq(object1.id.to_inner(), id1);

        withdraw.complete_withdraw();

        destroy(object2);
        destroy(object1);
        world.end();
    }

    #[test]
    fun test_borrow_end_to_end() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.scenario().next_tx(OWNER);

        let mut borrow = access::new_borrow(vector[id1, id2]);
        
        // Objects must be taken LIFO
        let object2 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id2));
        let object1 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id1));

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);

        borrow.put_back(world.multisig(), object1);
        borrow.put_back(world.multisig(), object2);

        world.scenario().next_tx(OWNER);

        let object1 = take_from_address_by_id<Object>(world.scenario(), multisig_address, id1);
        let object2 = take_from_address_by_id<Object>(world.scenario(), multisig_address, id2);

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);

        borrow.complete_borrow();
        
        destroy(object1);
        destroy(object2);
        world.end();
    }

    #[test]
    #[expected_failure(abort_code = access::EWrongObject)]
    fun test_withdraw_error_wrong_object() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object2, multisig_address);

        world.scenario().next_tx(OWNER);

        let mut borrow = access::new_borrow(vector[id1]);
        
        // Objects must be taken LIFO
        let object2 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id2));
        
        destroy(object1);
        destroy(object2);
        destroy(borrow);
        world.end();        
    }

    #[test]
    #[expected_failure(abort_code = access::EWrongObject)]
    fun test_put_back_error_wrong_object() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let mut borrow = access::new_borrow(vector[id1]);
        
        // Objects must be taken LIFO
        let object1 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id1));

        borrow.put_back(world.multisig(), object1);
        borrow.put_back(world.multisig(), object2);

        world.scenario().next_tx(OWNER);

        borrow.complete_borrow();
        
        world.end();
    }

    #[test]
    #[expected_failure(abort_code = access::ERetrieveAllObjectsBefore)]
    fun test_complete_borrow_error_retrieve_all_objects_before() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);


        world.scenario().next_tx(OWNER);

        let borrow = access::new_borrow(vector[id1]);

        borrow.complete_borrow();
        world.end();
    }

    #[test]
    #[expected_failure(abort_code = access::EReturnAllObjectsBefore)]
    fun test_complete_borrow_error_return_all_objects_before() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);

        world.scenario().next_tx(OWNER);

        let mut borrow = access::new_borrow(vector[id1]);

        let object1 = borrow.borrow<Object>(world.multisig(), receiving_ticket_by_id(id1));

        borrow.complete_borrow();
        destroy(object1);
        world.end();
    }

    fun new_object(ctx: &mut TxContext): Object {
        Object {
            id: object::new(ctx)
        }
    }
}

