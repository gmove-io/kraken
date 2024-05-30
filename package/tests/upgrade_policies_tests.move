#[test_only]
module kraken::upgrade_policies_tests {
    // use std::string::utf8;

    // use sui::package;

    // use sui::test_utils::{destroy, assert_eq};
    // use sui::test_scenario::{receiving_ticket_by_id, take_from_address_by_id, return_to_address};

    // use kraken::test_utils::start_world;
    // use kraken::upgrade_policies::{Self, Policy, UpgradeLock};

    // const OWNER: address = @0xBABE;

    // !IMPORTANT There is a bug on receiving_ticket_by_id. So the test below fails!
    // #[test]
    // fun test_upgrade_end_to_end() {
    //     let mut world = start_world();

    //     let package_id = object::new(world.scenario().ctx());

    //     let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());

    //     let lock_id = world.lock_cap(utf8(b"upgrade_cap 1"), 50, upgrade_cap);

    //     world.scenario().next_tx(OWNER);

    //     let digest = vector[0, 1, 0, 1];

    //     world.propose_upgrade(utf8(b"1"), 100, utf8(b"fix a bug"), digest, receiving_ticket_by_id(lock_id));

    //     world.clock().set_for_testing(151);
    //     world.scenario().next_tx(OWNER);

    //     world.approve_proposal(utf8(b"1"));

    //     world.scenario().next_tx(OWNER);

    //     let action = world.execute_proposal<Upgrade>(utf8(b"1")); 

    //     let (upgrade_ticket, lock) = upgrade_policies::execute_upgrade(
    //         action, 
    //         world.multisig(), 
    //         receiving_ticket_by_id(lock_id)
    //     );        

    //     upgrade_policies::complete_upgrade(
    //         world.multisig(), 
    //         lock, 
    //         upgrade_ticket.test_upgrade()
    //     );  

    //     destroy(package_id);        
    //     world.end();
    // }    

    // !IMPORTANT There is a bug on receiving_ticket_by_id. So the test below fails!
    // #[test]
    // fun test_new_policy_end_to_end() {
    //     let mut world = start_world();

    //     let package_id = object::new(world.scenario().ctx());

    //     let upgrade_cap = package::test_publish(package_id.to_inner(), world.scenario().ctx());

    //     let lock_id = world.lock_cap(utf8(b"upgrade_cap 1"), 50, upgrade_cap);

    //     world.scenario().next_tx(OWNER);

    //     world.propose_policy(utf8(b"1"), 100, 2, utf8(b"make additive"), 128, receiving_ticket_by_id(lock_id));

    //     world.clock().set_for_testing(151);
    //     world.scenario().next_epoch(OWNER);
    //     world.scenario().next_epoch(OWNER);
    //     world.scenario().next_tx(OWNER);

    //     world.approve_proposal(utf8(b"1"));

    //     world.scenario().next_tx(OWNER);

    //     let action = world.execute_proposal<Policy>(utf8(b"1")); 

    //     upgrade_policies::execute_policy(
    //         action, 
    //         world.multisig(), 
    //         receiving_ticket_by_id(lock_id)
    //     );  

    //     world.scenario().next_tx(OWNER);   

    //     let multisig_address = world.multisig().addr(); 

    //     let lock = take_from_address_by_id<UpgradeLock>(world.scenario(), multisig_address, lock_id);  

    //     assert_eq(lock.upgrade_cap().policy(), package::additive_policy()); 

    //     destroy(lock);
    //     destroy(package_id);        
    //     world.end();
    // }     
}