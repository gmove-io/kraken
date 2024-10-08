#[test_only]
module account_actions::actions_test_utils;

use std::string::String;
use sui::{
    package::UpgradeCap,
    transfer::Receiving,
    clock::{Self, Clock},
    coin::{Self, Coin, TreasuryCap},
    kiosk::{Kiosk, KioskOwnerCap},
    transfer_policy::{TransferPolicy, TransferRequest},
    test_utils::destroy,
    test_scenario::{Self as ts, Scenario, most_recent_id_for_address},
};
use account_protocol::{
    account::{Self, Account},
    proposals::Proposal,
    executable::Executable,
    user::{Self, User},
};
use account_actions::{
    owned,
    config,
    payments::{Self, Stream},
    currency,
    upgrade_policies::{Self, UpgradeLock},
    transfers,
    treasury,
    kiosk as k_kiosk,
};
use account_extensions::extensions::{Self, Extensions, AdminCap};

const OWNER: address = @0xBABE;

// hot potato holding the state
public struct World {
    scenario: Scenario,
    clock: Clock,
    user: User,
    account: Account,
    kiosk: Kiosk,
    extensions: Extensions,
    cap: AdminCap,
}

// === Utils ===

public fun start_world(): World {
    let mut scenario = ts::begin(OWNER);
    extensions::init_for_testing(scenario.ctx());

    scenario.next_tx(OWNER);
    let user = user::new(b"sam".to_string(), b"move_god.png".to_string(), scenario.ctx());
    let cap = scenario.take_from_sender<AdminCap>();
    let mut extensions = scenario.take_shared<Extensions>();

    // initialize Clock, Account, Extensions
    let clock = clock::create_for_testing(scenario.ctx());
    extensions.add(&cap, b"AccountProtocol".to_string(), @account_protocol, 1);
    extensions.add(&cap, b"AccountActions".to_string(), @account_actions, 1);
    let mut account = account::new(
        &extensions,
        b"Kraken".to_string(), 
        object::id(&user), 
        scenario.ctx()
    );
    k_kiosk::new(&mut account, b"kiosk".to_string(), scenario.ctx());

    scenario.next_tx(OWNER);
    let kiosk = scenario.take_shared<Kiosk>();

    World { scenario, clock, user, account, kiosk, extensions, cap }
}

public fun end(world: World) {
    let World { 
        scenario, 
        clock, 
        account, 
        user, 
        kiosk,
        extensions,
        cap
    } = world;

    destroy(clock);
    destroy(user);
    destroy(account);
    destroy(kiosk);
    destroy(extensions);
    destroy(cap);
    scenario.end();
}

public fun account(world: &mut World): &mut Account {
    &mut world.account
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

public fun last_id_for_account<T: key>(world: &World): ID {
    most_recent_id_for_address<T>(world.account.addr()).extract()
}

public fun role(module_name: vector<u8>): String {
    let mut role = @account_actions.to_string();
    role.append_utf8(b"::");
    role.append_utf8(module_name);
    role.append_utf8(b"::Auth");
    role
}

// === Account ===

public fun new_account(world: &mut World): Account {
    account::new(
        &world.extensions,
        b"kraken2".to_string(), 
        object::id(&world.user), 
        world.scenario.ctx()
    )
}

public fun create_proposal<W: copy + drop>(
    world: &mut World, 
    auth_witness: W,
    auth_name: String,
    key: String, 
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
): Proposal {
    world.account.create_proposal(
        auth_witness, 
        auth_name,
        key,
        description, 
        execution_time, 
        expiration_epoch, 
        world.scenario.ctx()
    )
}

public fun approve_proposal(
    world: &mut World, 
    key: String, 
) {
    world.account.approve_proposal(key, world.scenario.ctx());
}

public fun execute_proposal(
    world: &mut World, 
    key: String, 
): Executable {
    world.account.execute_proposal(key, &world.clock)
}

// === Config ===

public fun propose_config_name(
    world: &mut World,
    key: String,
    name: String
) {
    config::propose_config_name(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        name, 
        world.scenario.ctx()
    );
}

public fun propose_config_rules(
    world: &mut World, 
    key: String,
    addresses: vector<address>,
    weights: vector<u64>,
    roles: vector<vector<String>>,
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
) {
    config::propose_config_rules(
        &mut world.account, 
        key,
        b"".to_string(), 
        0, 
        0, 
        addresses,
        weights,
        roles,
        global,
        role_names,
        role_thresholds,     
        world.scenario.ctx()
    );
}

public fun propose_config_deps(
    world: &mut World, 
    key: String,
    names: vector<String>,
    packages: vector<address>,
    versions: vector<u64>,
) {
    config::propose_config_deps(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        &world.extensions,
        names,
        packages,
        versions,
        world.scenario.ctx()
    );
}

// === Currency ===

public fun lock_treasury_cap<C: drop>(world: &mut World, cap: TreasuryCap<C>, can_mint: bool) {
    currency::lock_cap(&mut world.account, cap, can_mint, world.scenario.ctx());
}

public fun propose_mint<C: drop>(
    world: &mut World, 
    key: String,    
    amount: u64
) {
    currency::propose_mint<C>(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        amount,
        world.scenario.ctx()
    );
}

public fun execute_mint<C: drop>(
    world: &mut World,
    executable: Executable,
) {
    currency::execute_mint<C>(executable, &mut world.account, world.scenario.ctx());
}

public fun propose_burn<C: drop>(
    world: &mut World, 
    key: String,
    coin_id: ID,
    amount: u64,
) {
    currency::propose_burn<C>(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        coin_id,
        amount,
        world.scenario.ctx()
    );
}

public fun propose_update<C: drop>(
    world: &mut World, 
    key: String,
    name: Option<String>,
    symbol: Option<String>,
    description_md: Option<String>,
    icon_url: Option<String>,
) {
    currency::propose_update<C>(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        name,
        symbol,
        description_md,
        icon_url,
        world.scenario.ctx()
    );
}

public fun propose_transfer_minted<C: drop>(
    world: &mut World, 
    key: String,
    amounts: vector<u64>,
    recipients: vector<address>,
) {
    currency::propose_transfer<C>(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        amounts,
        recipients, 
        world.scenario.ctx()
    );
}

public fun propose_pay_minted<C: drop>(
    world: &mut World,
    key: String,
    coin_amount: u64,
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
) {
    currency::propose_pay<C>(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        coin_amount,
        amount,
        interval,
        recipient,
        world.scenario.ctx()
    );
}

public fun execute_pay_minted<C: drop>(
    world: &mut World,
    executable: Executable, 
) {
    currency::execute_pay<C>(executable, &mut world.account, world.scenario.ctx());
}

// === Kiosk ===

public fun place<T: key + store>(
    world: &mut World, 
    sender_kiosk: &mut Kiosk, 
    sender_cap: &KioskOwnerCap, 
    name: String,
    nft_id: ID,
    policy: &mut TransferPolicy<T>,
): TransferRequest<T> {
    k_kiosk::place(
        &mut world.account,
        &mut world.kiosk,
        sender_kiosk,
        sender_cap,
        name,
        nft_id,
        policy,
        world.scenario.ctx()
    )
}

public fun propose_take(
    world: &mut World, 
    key: String,
    name: String,
    nft_ids: vector<ID>,
    recipient: address,
) {
    k_kiosk::propose_take(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        name,
        nft_ids,
        recipient,
        world.scenario.ctx()
    )
}

public fun execute_take<T: key + store>(
    world: &mut World, 
    executable: &mut Executable,
    recipient_kiosk: &mut Kiosk, 
    recipient_cap: &KioskOwnerCap, 
    policy: &mut TransferPolicy<T>
): TransferRequest<T> {
    k_kiosk::execute_take(
        executable,
        &mut world.account,
        &mut world.kiosk,
        recipient_kiosk,
        recipient_cap,
        policy,
        world.scenario.ctx()
    )
}

public fun propose_list(
    world: &mut World, 
    key: String,
    name: String,
    nft_ids: vector<ID>,
    prices: vector<u64>
) {
    k_kiosk::propose_list(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        name,
        nft_ids,
        prices,
        world.scenario.ctx()
    );
}

public fun execute_list<T: key + store>(
    world: &mut World,
    executable: &mut Executable,
) {
    k_kiosk::execute_list<T>(executable, &mut world.account, &mut world.kiosk);
}

// === Owned ===

public fun withdraw<O: key + store, W: copy + drop>(
    world: &mut World, 
    executable: &mut Executable,
    receiving: Receiving<O>,
    witness: W,
): O {
    owned::withdraw<O, W>(executable, &mut world.account, receiving, witness)
}

public fun borrow<O: key + store, W: copy + drop>(
    world: &mut World, 
    executable: &mut Executable,
    receiving: Receiving<O>,
    witness: W,
): O {
    owned::borrow<O, W>(executable, &mut world.account, receiving, witness)
}

public fun put_back<O: key + store, W: copy + drop>(
    world: &mut World, 
    executable: &mut Executable,
    returned: O,
    witness: W,
) {
    owned::put_back<O, W>(executable, &world.account, returned, witness);
}

public fun propose_transfer_owned(
    world: &mut World, 
    key: String,
    objects: vector<vector<ID>>,
    recipients: vector<address>
) {
    owned::propose_transfer(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        objects, 
        recipients, 
        world.scenario.ctx()
    );
}

public fun propose_pay_owned(
    world: &mut World,
    key: String,
    coin: ID, // must have the total amount to be paid
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
) {
    owned::propose_pay(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        coin,
        amount,
        interval,
        recipient,
        world.scenario.ctx()
    );
}

public fun execute_pay_owned<C: drop>(
    world: &mut World,
    executable: Executable, 
    receiving: Receiving<Coin<C>>,
) {
    owned::execute_pay<C>(executable, &mut world.account, receiving, world.scenario.ctx());
}

// === Payments ===

public fun cancel_payment_stream<C: drop>(
    world: &mut World,
    stream: Stream<C>,
) {
    payments::cancel_payment_stream(stream, &world.account, world.scenario.ctx());
}

// === Treasury ===

public fun deposit<C: drop>(
    world: &mut World,
    name: String,
    amount: u64,
) {
    treasury::deposit<C>(
        &mut world.account, 
        name, 
        coin::mint_for_testing<C>(amount, world.scenario.ctx()), 
        world.scenario.ctx()
    );
}

public fun close(
    world: &mut World,
    name: String,
) {
    treasury::close(&mut world.account, name, world.scenario.ctx());
}

public fun propose_open(
    world: &mut World,
    key: String,
    name: String,
) {
    treasury::propose_open(
        &mut world.account, 
        key,
        b"".to_string(), 
        0, 
        0, 
        name, 
        world.scenario.ctx()
    );
}

public fun execute_open(
    world: &mut World,
    executable: Executable,
) {
    treasury::execute_open(executable, &mut world.account, world.scenario.ctx());
}

public fun propose_transfer_treasury(
    world: &mut World, 
    key: String,
    treasury_name: String,
    coin_types: vector<vector<String>>,
    coin_amounts: vector<vector<u64>>,
    recipients: vector<address>,
) {
    treasury::propose_transfer(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        0, 
        treasury_name,
        coin_types,
        coin_amounts,
        recipients, 
        world.scenario.ctx()
    );
}

public fun propose_pay_treasury(
    world: &mut World,
    key: String,
    treasury_name: String, 
    coin_type: String, 
    coin_amount: u64, 
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
) {
    treasury::propose_pay(
        &mut world.account,
        key,
        b"".to_string(), 
        0, 
        0, 
        treasury_name,
        coin_type,
        coin_amount,
        amount,
        interval,
        recipient,
        world.scenario.ctx()
    );
}

public fun execute_pay_treasury<C: drop>(
    world: &mut World,
    executable: Executable, 
) {
    treasury::execute_pay<C>(executable, &mut world.account, world.scenario.ctx());
}

// === Upgrade Policies ===

public fun lock_cap(
    world: &mut World,
    upgrade_lock: UpgradeLock,
    label: String,
) {
    upgrade_lock.lock_cap(&mut world.account, label, world.scenario.ctx());
}

public fun lock_cap_with_timelock(
    world: &mut World,
    label: String,
    delay_ms: u64,
    upgrade_cap: UpgradeCap
) {
    upgrade_policies::lock_cap_with_timelock(&mut world.account, label, delay_ms, upgrade_cap, world.scenario.ctx());
}

public fun propose_upgrade(
    world: &mut World, 
    key: String,
    name: String,
    digest: vector<u8>,
) {
    upgrade_policies::propose_upgrade(
        &mut world.account, 
        key, 
        b"".to_string(), 
        0, 
        name,
        digest, 
        &world.clock, 
        world.scenario.ctx()
    ); 
}

public fun propose_restrict(
    world: &mut World, 
    key: String,
    name: String,
    policy: u8,
) {
    upgrade_policies::propose_restrict(
        &mut world.account, 
        key, 
        b"".to_string(),
        0, 
        name, 
        policy, 
        &world.clock, 
        world.scenario.ctx()
    );
}