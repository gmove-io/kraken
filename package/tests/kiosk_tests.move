#[test_only]
module kraken::kiosk_tests{
    use std::string::utf8;
    use std::debug::print;

    use sui::transfer_policy;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::coin::mint_for_testing;
    use sui::test_utils::{destroy, assert_eq};
    use sui::test_scenario::{take_shared, receiving_ticket_by_id};

    use kraken::test_utils::start_world;
    use kraken::kiosk::{Self as k_kiosk, Transfer, List};

    const OWNER: address = @0xBABE;
    const ALICE: address = @0xA11CE;

    public struct NFT has key, store {
        id: UID
    }

    #[test]
    fun test_transfer_from() {
        let mut world = start_world();

        let (mut multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        let multisig_kiosk_cap_id = object::id(&multisig_kiosk_cap);
        transfer::public_transfer(multisig_kiosk_cap, world.multisig().addr());

        world.scenario().next_tx(OWNER);

        let (mut sender_kiosk, sender_cap) = kiosk::new(world.scenario().ctx());

        let nft = new_nft(world.scenario().ctx());
        let (policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

        let nft_id = object::id(&nft);

        sender_kiosk.place(&sender_cap, nft);

        assert_eq(kiosk::has_item(&multisig_kiosk, nft_id), false);

        let request = world.transfer_from<NFT>(
            &mut multisig_kiosk,
            receiving_ticket_by_id(multisig_kiosk_cap_id),
            &mut sender_kiosk,
            &sender_cap,
            nft_id
        );

        transfer_policy::confirm_request(&policy, request);

        assert_eq(kiosk::has_item(&multisig_kiosk, nft_id), true);

        destroy(policy);
        destroy(policy_cap);
        destroy(multisig_kiosk);
        destroy(sender_kiosk);
        destroy(sender_cap);
        world.end();
    }

    #[test]
    fun test_transfer_to_end_to_end() {
        let mut world = start_world();

        let (mut multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        let multisig_kiosk_cap_id = object::id(&multisig_kiosk_cap);
        transfer::public_transfer(multisig_kiosk_cap, world.multisig().addr());

        world.scenario().next_tx(OWNER);

        let (mut receiver_kiosk, receiver_cap) = kiosk::new(world.scenario().ctx());

        let nft = new_nft(world.scenario().ctx());
        let nft2 = new_nft(world.scenario().ctx());
        let (policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

        let nft_id = object::id(&nft);
        let nft2_id = object::id(&nft2);

        world.scenario().next_tx(OWNER);

        world.propose_transfer_to(
            utf8(b"1"),
            25,
            2,
            utf8(b"take NFT"),
            multisig_kiosk_cap_id,
            vector[nft_id, nft2_id],
            OWNER
        );

        world.scenario().next_tx(OWNER);
        world.approve_proposal(utf8(b"1"));

        world.clock().set_for_testing(26);
        world.scenario().next_epoch(ALICE);
        world.scenario().next_epoch(OWNER);

        let mut action = world.execute_proposal<Transfer>(utf8(b"1"));

        let multisig_cap = k_kiosk::borrow_cap_transfer(
            &mut action, 
            world.multisig(), 
            receiving_ticket_by_id(multisig_kiosk_cap_id)
        );

        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft);
        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft2);

        assert_eq(kiosk::has_item(&multisig_kiosk, nft_id), true);
        assert_eq(kiosk::has_item(&multisig_kiosk, nft2_id), true);

        let request =  k_kiosk::transfer_to<NFT>(
            &mut action,
            &mut multisig_kiosk,
            &multisig_cap,
            &mut receiver_kiosk,
            &receiver_cap,
            world.scenario().ctx()
        );

        let request2 =  k_kiosk::transfer_to<NFT>(
            &mut action,
            &mut multisig_kiosk,
            &multisig_cap,
            &mut receiver_kiosk,
            &receiver_cap,
            world.scenario().ctx()
        );

        k_kiosk::complete_request(&policy, request);
        k_kiosk::complete_request(&policy, request2);

        k_kiosk::complete_transfer_to(action, world.multisig(), multisig_cap);

        assert_eq(kiosk::has_item(&multisig_kiosk, nft_id), false);
        assert_eq(kiosk::has_item(&multisig_kiosk, nft2_id), false);

        destroy(policy);
        destroy(policy_cap);
        destroy(multisig_kiosk);
        destroy(receiver_kiosk);
        destroy(receiver_cap);
        world.end();   
    }

    #[test]
    fun test_list_end_to_end() {
        let mut world = start_world();

        let (mut multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        let multisig_kiosk_cap_id = object::id(&multisig_kiosk_cap);
        transfer::public_transfer(multisig_kiosk_cap, world.multisig().addr());

        world.scenario().next_tx(OWNER);

        let (receiver_kiosk, receiver_cap) = kiosk::new(world.scenario().ctx());

        let nft = new_nft(world.scenario().ctx());
        let nft2 = new_nft(world.scenario().ctx());
        let (policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

        let nft_id = object::id(&nft);
        let nft2_id = object::id(&nft2);

        world.scenario().next_tx(OWNER);

        world.propose_list(
            utf8(b"1"),
            25,
            2,
            utf8(b"take NFT"),
            multisig_kiosk_cap_id,
            vector[nft_id, nft2_id],
            vector[10, 15]
        );

        world.scenario().next_tx(OWNER);
        world.approve_proposal(utf8(b"1"));

        world.clock().set_for_testing(26);
        world.scenario().next_epoch(ALICE);
        world.scenario().next_epoch(OWNER);

        let mut action = world.execute_proposal<List>(utf8(b"1"));

        let multisig_cap = k_kiosk::borrow_cap_list(
            &mut action, 
            world.multisig(), 
            receiving_ticket_by_id(multisig_kiosk_cap_id)
        );

        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft);
        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft2);

        assert_eq(kiosk::is_listed(&multisig_kiosk, nft_id), false);
        assert_eq(kiosk::is_listed(&multisig_kiosk, nft2_id), false);

        k_kiosk::list<NFT>(&mut action, &mut multisig_kiosk, &multisig_cap);
        k_kiosk::list<NFT>(&mut action, &mut multisig_kiosk, &multisig_cap);

        let (nft, request) = multisig_kiosk.purchase<NFT>(nft_id, mint_for_testing(10, world.scenario().ctx()));

        world.withdraw_profits(&mut multisig_kiosk, &multisig_cap);

        k_kiosk::complete_list(action, world.multisig(), multisig_cap);

        assert_eq(kiosk::is_listed(&multisig_kiosk, nft_id), false);
        assert_eq(kiosk::is_listed(&multisig_kiosk, nft2_id), true);

        world.scenario().next_tx(ALICE);

        destroy(nft);
        destroy(request);
        destroy(policy);
        destroy(policy_cap);
        destroy(multisig_kiosk);
        destroy(receiver_kiosk);
        destroy(receiver_cap);
        world.end();        
    }

    #[test]
    #[expected_failure(abort_code = k_kiosk::EWrongReceiver)]
    fun test_transfer_to_error_wrong_receiver() {
        let mut world = start_world();

        let (mut multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        let multisig_kiosk_cap_id = object::id(&multisig_kiosk_cap);
        transfer::public_transfer(multisig_kiosk_cap, world.multisig().addr());

        world.scenario().next_tx(OWNER);

        let (mut receiver_kiosk, receiver_cap) = kiosk::new(world.scenario().ctx());

        let nft = new_nft(world.scenario().ctx());
        let (policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

        let nft_id = object::id(&nft);

        world.scenario().next_tx(OWNER);

        world.propose_transfer_to(
            utf8(b"1"),
            25,
            2,
            utf8(b"take NFT"),
            multisig_kiosk_cap_id,
            vector[nft_id],
            ALICE
        );

        world.scenario().next_tx(OWNER);
        world.approve_proposal(utf8(b"1"));

        world.clock().set_for_testing(26);
        world.scenario().next_epoch(ALICE);
        world.scenario().next_epoch(OWNER);

        let mut action = world.execute_proposal<Transfer>(utf8(b"1"));

        let multisig_cap = k_kiosk::borrow_cap_transfer(
            &mut action, 
            world.multisig(), 
            receiving_ticket_by_id(multisig_kiosk_cap_id)
        );

        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft);

        let request =  k_kiosk::transfer_to<NFT>(
            &mut action,
            &mut multisig_kiosk,
            &multisig_cap,
            &mut receiver_kiosk,
            &receiver_cap,
            world.scenario().ctx()
        );

        k_kiosk::complete_request(&policy, request);

        k_kiosk::complete_transfer_to(action, world.multisig(), multisig_cap);

        destroy(policy);
        destroy(policy_cap);
        destroy(multisig_kiosk);
        destroy(receiver_kiosk);
        destroy(receiver_cap);
        world.end();   
    }

    #[test]
    #[expected_failure(abort_code = k_kiosk::ETransferAllNftsBefore)]
    fun test_transfer_to_error_transfer_all_nfts_before() {
        let mut world = start_world();

        let (mut multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        let multisig_kiosk_cap_id = object::id(&multisig_kiosk_cap);
        transfer::public_transfer(multisig_kiosk_cap, world.multisig().addr());

        world.scenario().next_tx(OWNER);

        let (mut receiver_kiosk, receiver_cap) = kiosk::new(world.scenario().ctx());

        let nft = new_nft(world.scenario().ctx());
        let nft2 = new_nft(world.scenario().ctx());
        let (policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

        let nft_id = object::id(&nft);
        let nft2_id = object::id(&nft2);

        world.scenario().next_tx(OWNER);

        world.propose_transfer_to(
            utf8(b"1"),
            25,
            2,
            utf8(b"take NFT"),
            multisig_kiosk_cap_id,
            vector[nft_id, nft2_id],
            OWNER
        );

        world.scenario().next_tx(OWNER);
        world.approve_proposal(utf8(b"1"));

        world.clock().set_for_testing(26);
        world.scenario().next_epoch(ALICE);
        world.scenario().next_epoch(OWNER);

        let mut action = world.execute_proposal<Transfer>(utf8(b"1"));

        let multisig_cap = k_kiosk::borrow_cap_transfer(
            &mut action, 
            world.multisig(), 
            receiving_ticket_by_id(multisig_kiosk_cap_id)
        );

        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft);
        k_kiosk::place(&mut multisig_kiosk, &multisig_cap, nft2);

        let request =  k_kiosk::transfer_to<NFT>(
            &mut action,
            &mut multisig_kiosk,
            &multisig_cap,
            &mut receiver_kiosk,
            &receiver_cap,
            world.scenario().ctx()
        );

        k_kiosk::complete_request(&policy, request);

        k_kiosk::complete_transfer_to(action, world.multisig(), multisig_cap);

        destroy(policy);
        destroy(policy_cap);
        destroy(multisig_kiosk);
        destroy(receiver_kiosk);
        destroy(receiver_cap);
        world.end();   
    }

    #[test]
    #[expected_failure(abort_code = k_kiosk::EWrongNftsPrices)]
    fun test_propose_list_error_wrong_nfts_price() {
        let mut world = start_world();

        let (multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        let multisig_kiosk_cap_id = object::id(&multisig_kiosk_cap);
        transfer::public_transfer(multisig_kiosk_cap, world.multisig().addr());

        world.scenario().next_tx(OWNER);

        let (receiver_kiosk, receiver_cap) = kiosk::new(world.scenario().ctx());

        let nft = new_nft(world.scenario().ctx());
        let nft2 = new_nft(world.scenario().ctx());
        let (policy, policy_cap) = transfer_policy::new_for_testing<NFT>(world.scenario().ctx());

        let nft_id = object::id(&nft);
        let nft2_id = object::id(&nft2);

        world.scenario().next_tx(OWNER);

        world.propose_list(
            utf8(b"1"),
            25,
            2,
            utf8(b"take NFT"),
            multisig_kiosk_cap_id,
            vector[nft_id, nft2_id],
            vector[10, 15, 23]
        );

        destroy(nft);
        destroy(nft2);
        destroy(policy);
        destroy(policy_cap);
        destroy(multisig_kiosk);
        destroy(receiver_kiosk);
        destroy(receiver_cap);
        world.end();        
    }

    #[test]
    #[expected_failure]
    fun new_error_not_a_member() {
        let mut world = start_world();

        world.scenario().next_tx(ALICE);

        let (mut multisig_kiosk, multisig_kiosk_cap) = world.new_kiosk();
        
        destroy(multisig_kiosk);
        destroy(multisig_kiosk_cap);
        world.end();        
    }

    fun new_nft(ctx: &mut TxContext): NFT {
        NFT {
            id: object::new(ctx)
        }
    }
}