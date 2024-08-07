#[test_only]
module kraken::test_utils {
    use std::string::{Self, String};

    use sui::{
        bag::Bag,
        test_utils::destroy,
        package::UpgradeCap,
        transfer::Receiving,
        clock::{Self, Clock},
        coin::{Coin, TreasuryCap},
        kiosk::{Kiosk, KioskOwnerCap},
        transfer_policy::TransferPolicy,
        test_scenario::{Self as ts, Scenario, receiving_ticket_by_id, most_recent_id_for_address},
    };

    use kraken::{
        owned,
        config,
        coin_operations,
        payments::{Self, Stream},
        currency::{Self, TreasuryLock},
        account::{Self, Account, Invite},
        upgrade_policies::{Self, UpgradeLock},
        transfers::{Self, DeliveryCap, Delivery},
        kiosk::{Self as k_kiosk, KioskOwnerLock},
        multisig::{Self, Multisig, Proposal, Executable},
    };

    const OWNER: address = @0xBABE;

    // hot potato holding the state
    public struct World {
        account: Account,
        scenario: Scenario,
        clock: Clock,
        multisig: Multisig,
        kiosk: Kiosk,
        kiosk_owner_lock_id: ID
    }

    public struct Obj has key, store { id: UID }

    // === Utils ===

    public fun start_world(): World {
        let mut scenario = ts::begin(OWNER);
        account::new(string::utf8(b"sam"), string::utf8(b"move_god.png"), scenario.ctx());

        scenario.next_tx(OWNER);

        let account = scenario.take_from_sender<Account>();

        // initialize multisig and clock
        let multisig = multisig::new(string::utf8(b"kraken"), object::id(&account), scenario.ctx());
        let clock = clock::create_for_testing(scenario.ctx());

        k_kiosk::new(&multisig, scenario.ctx());

        scenario.next_tx(OWNER);

        let kiosk_owner_lock_id = most_recent_id_for_address<KioskOwnerLock>(multisig.addr()).extract();

        let kiosk = scenario.take_shared<Kiosk>();

        World { scenario, clock, multisig, account, kiosk, kiosk_owner_lock_id }
    }

    public fun multisig(world: &mut World): &mut Multisig {
        &mut world.multisig
    }

    public fun clock(world: &mut World): &mut Clock {
        &mut world.clock
    }

    public fun kiosk(world: &mut World): &mut Kiosk {
        &mut world.kiosk
    }

    public fun scenario(world: &mut World): &mut Scenario {
        &mut world.scenario
    }

    public fun last_id_for_multisig<T: key>(world: &World): ID {
        most_recent_id_for_address<T>(world.multisig.addr()).extract()
    }
    
    public fun new_multisig(world: &mut World): Multisig {
        multisig::new(string::utf8(b"kraken2"), object::id(&world.account), world.scenario.ctx())
    }

    public fun withdraw<Object: key + store, Witness: drop + copy>(
        world: &mut World, 
        executable: &mut Executable,
        receiving: Receiving<Object>,
        witness: Witness,
        idx: u64
    ): Object {
        owned::withdraw<Object, Witness>(executable, &mut world.multisig, receiving, witness, idx)
    }

    public fun put_back<Object: key + store, Witness: drop + copy>(
        world: &mut World, 
        executable: &mut Executable,
        returned: Object,
        witness: Witness,
        idx: u64
    ) {
        owned::put_back<Object, Witness>(executable, &world.multisig, returned, witness, idx);
    }

    public fun borrow<Object: key + store, Witness: drop + copy>(
        world: &mut World, 
        executable: &mut Executable,
        receiving: Receiving<Object>,
        witness: Witness,
        idx: u64
    ): Object {
        owned::borrow<Object, Witness>(executable, &mut world.multisig, receiving, witness, idx)
    }

    public fun create_proposal<Witness: drop>(
        world: &mut World, 
        witness: Witness,
        key: String, 
        execution_time: u64, // timestamp in ms
        expiration_epoch: u64,
        description: String
    ): &mut Proposal {
        world.multisig.create_proposal(
            witness, 
            key,
            execution_time, 
            expiration_epoch, 
            description, 
            world.scenario.ctx()
        )
    }

    public fun approve_proposal(
        world: &mut World, 
        key: String, 
    ) {
        world.multisig.approve_proposal(key, world.scenario.ctx());
    }

    public fun remove_approval(
        world: &mut World, 
        key: String, 
    ) {
        world.multisig.remove_approval(key, world.scenario.ctx());
    }

    public fun delete_proposal(
        world: &mut World, 
        key: String
    ): Bag {
        world.multisig.delete_proposal(key, world.scenario.ctx())
    }

    public fun execute_proposal(
        world: &mut World, 
        key: String, 
    ): Executable {
        world.multisig.execute_proposal(key, &world.clock, world.scenario.ctx())
    }

    public fun merge_and_split<T: drop>(
        world: &mut World, 
        to_merge: vector<Receiving<Coin<T>>>,
        to_split: vector<u64> 
    ): vector<ID> {
        coin_operations::merge_and_split(&mut world.multisig, to_merge, to_split, world.scenario.ctx())
    }

    public fun join_multisig(
        world: &mut World, 
        account: &mut Account
    ) {
        account::join_multisig(account, &mut world.multisig, world.scenario.ctx());
    }

    public fun leave_multisig(
        world: &mut World, 
        account: &mut Account
    ) {
        account::leave_multisig(account, &mut world.multisig, world.scenario.ctx());
    }

    public fun send_invite(
        world: &mut World, 
        recipient: address
    ) {
        account::send_invite(&world.multisig, recipient, world.scenario.ctx());
    }    

    public fun accept_invite(
        world: &mut World, 
        account: &mut Account,
        invite: Invite
    ) {
        account::accept_invite(account, &mut world.multisig, invite, world.scenario.ctx());
    }    

    public fun register_account_id(
        world: &mut World, 
        id: ID,
    ) {
        world.multisig.register_account_id(id, world.scenario.ctx());
    }     

    public fun unregister_account_id(
        world: &mut World, 
    ) {
        world.multisig.unregister_account_id(world.scenario.ctx());
    }  


    public fun assert_is_member(
        world: &mut World, 
    ) {
        multisig::assert_is_member(&world.multisig, world.scenario.ctx());
    }

    public fun propose_modify(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: Option<String>,
        threshold: Option<u64>, 
        to_remove: vector<address>, 
        to_add: vector<address>, 
        weights: vector<u64>
    ) {
        config::propose_modify(
            &mut world.multisig, 
            key, 
            execution_time, 
            expiration_epoch, 
            description, 
            name, 
            threshold, 
            to_remove, 
            to_add, 
            weights,
            world.scenario.ctx()
        );
    }

    public fun propose_migrate(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        version: u64
    ) {
        config::propose_migrate(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            version,
            world.scenario.ctx()
        );
    }

    public fun borrow_cap(world: &mut World): KioskOwnerLock {
        k_kiosk::borrow_cap(&mut world.multisig, receiving_ticket_by_id(world.kiosk_owner_lock_id), world.scenario.ctx())
    }

    public fun place<T: key + store>(
        world: &mut World, 
        lock: &KioskOwnerLock,
        sender_kiosk: &mut Kiosk, 
        sender_cap: &KioskOwnerCap, 
        nft_id: ID,
        policy: &mut TransferPolicy<T>,
    ) {
        k_kiosk::place(
            &mut world.multisig,
            &mut world.kiosk,
            lock,
            sender_kiosk,
            sender_cap,
            nft_id,
            policy,
            world.scenario.ctx()
        )
    }

    public fun propose_take(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nft_ids: vector<ID>,
        recipient: address,
    ) {
        k_kiosk::propose_take(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            nft_ids,
            recipient,
            world.scenario.ctx()
        )
    }

    public fun execute_take<T: key + store>(
        world: &mut World, 
        executable: &mut Executable,
        lock: &KioskOwnerLock,
        recipient_kiosk: &mut Kiosk, 
        recipient_cap: &KioskOwnerCap, 
        policy: &mut TransferPolicy<T>
    ) {
        k_kiosk::execute_take(
            executable,
            &mut world.kiosk,
            lock,
            recipient_kiosk,
            recipient_cap,
            policy,
            world.scenario.ctx()
        );
    }

    public fun propose_list(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        nft_ids: vector<ID>,
        prices: vector<u64>
    ) {
        k_kiosk::propose_list(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            nft_ids,
            prices,
            world.scenario.ctx()
        );
    }

    public fun execute_list<T: key + store>(
        world: &mut World,
        executable: &mut Executable,
        lock: &KioskOwnerLock,
    ) {
        k_kiosk::execute_list<T>(executable, &mut world.kiosk, lock);
    }

    public fun propose_pay(
        world: &mut World,
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        coin: ID, // must have the total amount to be paid
        amount: u64, // amount to be paid at each interval
        interval: u64, // number of epochs between each payment
        recipient: address,
    ) {
        payments::propose_pay(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            coin,
            amount,
            interval,
            recipient,
            world.scenario.ctx()
        );
    }

    public fun execute_pay<C: drop>(
        world: &mut World,
        executable: Executable, 
        receiving: Receiving<Coin<C>>
    ) {
        payments::execute_pay<C>(executable, &mut world.multisig, receiving, world.scenario.ctx());
    }

    public fun cancel_payment_stream<C: drop>(
        world: &mut World,
        stream: Stream<C>,
    ) {
        payments::cancel_payment_stream(stream, &world.multisig, world.scenario.ctx());
    }

    public fun propose_send(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        recipients: vector<address>
    ) {
        transfers::propose_send(&mut world.multisig, key, execution_time, expiration_epoch, description, objects, recipients, world.scenario.ctx());
    }

    public fun propose_delivery(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        objects: vector<ID>,
        recipient: address
    ) {
        transfers::propose_delivery(&mut world.multisig, key, execution_time, expiration_epoch, description, objects, recipient, world.scenario.ctx());
    }

    public fun propose_mint<C: drop>(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        amount: u64
    ) {
        currency::propose_mint<C>(
            &mut world.multisig, 
            key, 
            execution_time, 
            expiration_epoch,
            description,
            amount,
            world.scenario.ctx()
        );
    }

    public fun propose_burn<C: drop>(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        coin_id: ID,
        amount: u64,
    ) {
        currency::propose_burn<C>(
            &mut world.multisig, 
            key, 
            execution_time, 
            expiration_epoch,
            description,
            coin_id,
            amount,
            world.scenario.ctx()
        );
    }

    public fun propose_update(
        world: &mut World, 
        key: String,
        execution_time: u64,
        expiration_epoch: u64,
        description: String,
        name: Option<String>,
        symbol: Option<String>,
        description_md: Option<String>,
        icon_url: Option<String>,
    ) {
        currency::propose_update(
            &mut world.multisig,
            key,
            execution_time,
            expiration_epoch,
            description,
            name,
            symbol,
            description_md,
            icon_url,
            world.scenario.ctx()
        );
    }

    public fun create_delivery(
        world: &mut World, 
    ): (Delivery, DeliveryCap) {
        transfers::create_delivery(&world.multisig, world.scenario.ctx())
    }

    public fun cancel_delivery(
        world: &mut World, 
        delivery: Delivery, 
    ) {
        transfers::cancel_delivery(&world.multisig, delivery, world.scenario.ctx());
    }

    public fun retrieve<T: key + store>(
        world: &mut World,
        delivery: &mut Delivery, 
    ) {
        transfers::retrieve<T>(delivery, &world.multisig, world.scenario.ctx());
    }

    public fun propose_upgrade(
        world: &mut World, 
        key: String,
        expiration_epoch: u64,
        description: String,
        digest: vector<u8>,
        lock: &UpgradeLock
    ) {
        upgrade_policies::propose_upgrade(&mut world.multisig, key, expiration_epoch, description, digest, lock, &world.clock, world.scenario.ctx()); 
    }

    public fun propose_restrict(
        world: &mut World, 
        key: String,
        expiration_epoch: u64,
        description: String,
        policy: u8,
        lock: &UpgradeLock
    ) {
        upgrade_policies::propose_restrict(&mut world.multisig, key, expiration_epoch, description, policy, lock, &world.clock, world.scenario.ctx());
    }

    public fun lock_cap(
        world: &mut World,
        label: String,
        upgrade_cap: UpgradeCap
    ): UpgradeLock {
        upgrade_policies::lock_cap(&world.multisig, label, upgrade_cap, world.scenario.ctx())    
    }

    public fun borrow_upgrade_cap_lock(
        world: &mut World, 
        lock: Receiving<UpgradeLock>
    ): UpgradeLock {
        upgrade_policies::borrow_cap(&mut world.multisig, lock, world.scenario.ctx())
    }

    public fun lock_cap_with_timelock(
        world: &mut World,
        label: String,
        delay_ms: u64,
        upgrade_cap: UpgradeCap
    ) {
        upgrade_policies::lock_cap_with_timelock(&world.multisig, label, delay_ms, upgrade_cap, world.scenario.ctx());
    }

    public fun lock_treasury_cap<C: drop>(world: &mut World, cap: TreasuryCap<C>) {
        currency::lock_cap(&world.multisig, cap, world.scenario.ctx());
    }

    public fun borrow_treasury_cap<C: drop>(world: &mut World, treasury_lock: Receiving<TreasuryLock<C>>): TreasuryLock<C> {
        currency::borrow_cap(&mut world.multisig, treasury_lock, world.scenario.ctx())
    }

    public fun end(world: World) {
        let World { 
            scenario, 
            clock, 
            multisig, 
            account, 
            kiosk,
            kiosk_owner_lock_id: _ 
        } = world;

        destroy(clock);
        destroy(kiosk);
        destroy(account);
        destroy(multisig);
        scenario.end();
    }
}