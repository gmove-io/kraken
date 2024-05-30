#[test_only]
module kraken::transfers_tests {
    use std::string::utf8;

    use sui::test_utils::{destroy, assert_eq};
    use sui::test_scenario::{
        receiving_ticket_by_id, 
        take_from_address_by_id, 
        take_from_address, 
        take_shared
    };

    use kraken::test_utils::start_world;
    use kraken::transfers::{Self, Send, Delivery, Deliver, DeliveryCap};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;

    public struct Object has key, store {
        id: UID
    }

    #[test]
    fun test_send_end_to_end() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_send(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            vector[OWNER, ALICE]
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Send>(utf8(b"1"));

        world.send<Object>(&mut action, receiving_ticket_by_id(id2));
        world.send<Object>(&mut action, receiving_ticket_by_id(id1));

        world.scenario().next_tx(OWNER);

        let object1 = take_from_address_by_id<Object>(world.scenario(), OWNER, id1);
        let object2 = take_from_address_by_id<Object>(world.scenario(), ALICE, id2);

        transfers::complete_send(action);

        destroy(object1);
        destroy(object2);
        world.end();
    }

    #[test]
    fun test_delivery_end_to_end() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_delivery(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            ALICE
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Deliver>(utf8(b"1"));

        let mut delivery = transfers::create_delivery(world.scenario().ctx());

        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id2));
        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id1));

        transfers::deliver(delivery, action, world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        world.scenario().next_tx(ALICE);

        let mut delivery = take_shared<Delivery>(world.scenario());
        let delivery_cap = take_from_address<DeliveryCap>(world.scenario(), ALICE);

        let object1 = transfers::claim<Object>(&mut delivery, &delivery_cap);
        let object2 = transfers::claim<Object>(&mut delivery, &delivery_cap);

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);

        transfers::complete_delivery(delivery, delivery_cap);

        destroy(object1);
        destroy(object2);
        world.end();        
    }

    #[test]
    fun test_retrieve() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_delivery(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            ALICE
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Deliver>(utf8(b"1"));
        let mut delivery = transfers::create_delivery(world.scenario().ctx());

        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id2));
        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id1));

        transfers::deliver(delivery, action, world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        let mut delivery = take_shared<Delivery>(world.scenario());

        world.retrieve<Object>(&mut delivery);
        world.retrieve<Object>(&mut delivery);

        world.scenario().next_tx(OWNER);
        
        let multisig_address = world.multisig().addr();

        let object1 = take_from_address_by_id<Object>(world.scenario(), multisig_address, id1);
        let object2 = take_from_address_by_id<Object>(world.scenario(), multisig_address, id2);        

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);        

        world.cancel_delivery(delivery);

        destroy(object1);
        destroy(object2);
        world.end();
    }

    #[test]
    #[expected_failure(abort_code = transfers::EDifferentLength)]
    fun test_propose_send_error_different_length() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        world.propose_send(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            vector[OWNER]
        );        

        destroy(object1);
        destroy(object2);
        world.end();
    }    

    #[test]
    #[expected_failure(abort_code = transfers::ESendAllAssetsBefore)]
    fun test_complete_send_error_send_all_assets_before() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_send(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            vector[OWNER, ALICE]
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Send>(utf8(b"1"));

        world.send<Object>(&mut action, receiving_ticket_by_id(id2));

        world.scenario().next_tx(OWNER);

        transfers::complete_send(action);

        world.end();
    }    

    #[test]
    #[expected_failure(abort_code = transfers::EDeliveryNotEmpty)]
    fun test_complete_delivery_error_delivery_not_empty() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_delivery(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            ALICE
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Deliver>(utf8(b"1"));

        let mut delivery = transfers::create_delivery(world.scenario().ctx());

        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id2));
        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id1));

        transfers::deliver(delivery, action, world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        world.scenario().next_tx(ALICE);

        let mut delivery = take_shared<Delivery>(world.scenario());
        let delivery_cap = take_from_address<DeliveryCap>(world.scenario(), ALICE);

        let object1 = transfers::claim<Object>(&mut delivery, &delivery_cap);

        transfers::complete_delivery(delivery, delivery_cap);

        destroy(object1);
        world.end();        
    }

    #[test]
    #[expected_failure(abort_code = transfers::EDeliveryNotEmpty)]
    fun test_cancel_delivery_error_delivery_not_empty() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_delivery(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            ALICE
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Deliver>(utf8(b"1"));
        let mut delivery = transfers::create_delivery(world.scenario().ctx());

        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id2));
        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id1));

        transfers::deliver(delivery, action, world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        let mut delivery = take_shared<Delivery>(world.scenario());

        world.retrieve<Object>(&mut delivery);

        world.scenario().next_tx(OWNER);
        
        world.cancel_delivery(delivery);

        world.end();
    }

    #[test]
    #[expected_failure(abort_code = transfers::EWrongDelivery)]
    fun test_claim_error_wrong_deliver() {
        let mut world = start_world();

        let object1 = new_object(world.scenario().ctx());
        let object2 = new_object(world.scenario().ctx());

        let id1 = object::id(&object1);
        let id2 = object::id(&object2);

        let multisig_address = world.multisig().addr();

        transfer::public_transfer(object1, multisig_address);
        transfer::public_transfer(object2, multisig_address);

        world.propose_delivery(
            utf8(b"1"), 
            100, 
            1, 
            utf8(b"send objects"), 
            vector[id1, id2],
            ALICE
        );

        world.scenario().next_epoch(OWNER);
        world.clock().set_for_testing(101);

        world.approve_proposal(utf8(b"1"));

        world.scenario().next_tx(OWNER);

        let mut action = world.execute_proposal<Deliver>(utf8(b"1"));

        let mut delivery = transfers::create_delivery(world.scenario().ctx());
        let mut wrong_delivery = transfers::create_delivery(world.scenario().ctx());

        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id2));
        transfers::add_to_delivery<Object>(&mut delivery, &mut action, world.multisig(), receiving_ticket_by_id(id1));

        transfers::deliver(delivery, action, world.scenario().ctx());

        world.scenario().next_tx(OWNER);

        world.scenario().next_tx(ALICE);

        let mut delivery = take_shared<Delivery>(world.scenario());
        let delivery_cap = take_from_address<DeliveryCap>(world.scenario(), ALICE);

        let object1 = transfers::claim<Object>(&mut delivery, &delivery_cap);
        let object2 = transfers::claim<Object>(&mut wrong_delivery, &delivery_cap);

        assert_eq(object::id(&object1), id1);
        assert_eq(object::id(&object2), id2);

        transfers::complete_delivery(delivery, delivery_cap);

        destroy(wrong_delivery);
        destroy(object1);
        destroy(object2);
        world.end();        
    }

    fun new_object(ctx: &mut TxContext): Object {
        Object {
            id: object::new(ctx)
        }
    }
}