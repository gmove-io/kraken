/// Members can lock a TreasuryCap in the Account to restrict minting and burning operations.
/// as well as modifying the CoinMetadata
/// Members can propose to mint a Coin that will be sent to the Account and burn one of its coin.
/// It uses a Withdraw action. The burnt Coin could be merged beforehand.
/// 
/// Coins minted by the account can also be transferred or paid to any address.

module account_actions::currency;

// === Imports ===

use std::{
    type_name,
    string::{Self, String}
};
use sui::{
    transfer::Receiving,
    coin::{Coin, TreasuryCap, CoinMetadata},
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth
};
use account_actions::{
    owned,
    transfers,
    payments,
};

// === Errors ===

const ENoChange: u64 = 0;
const EUpdateNotExecuted: u64 = 1;
const EWrongValue: u64 = 2;
const EMintNotExecuted: u64 = 3;
const EBurnNotExecuted: u64 = 4;
const ENoLock: u64 = 5;
const EDifferentLength: u64 = 6;
const EMintDisabled: u64 = 7;

// === Structs ===    

/// Dynamic Field key for the CurrencyLock
public struct CurrencyKey<phantom C: drop> has copy, drop, store {}
/// Dynamic Field wrapper restricting access to a TreasuryCap
public struct CurrencyLock<phantom C: drop> has store {
    // coins can be minted or no, coins can always be burnt by the owners
    can_mint: bool,
    // the cap to lock
    treasury_cap: TreasuryCap<C>,
}

/// [MEMBER] can lock a TreasuryCap in the Account to restrict minting and burning operations
public struct Do() has drop;
/// [PROPOSAL] mints new coins from a locked TreasuryCap
public struct MintProposal() has drop;
/// [PROPOSAL] burns coins from the account using a locked TreasuryCap
public struct BurnProposal() has drop;
/// [PROPOSAL] updates the CoinMetadata associated with a locked TreasuryCap
public struct UpdateProposal() has drop;
/// [PROPOSAL] transfers from a minted coin 
public struct TransferProposal() has drop;
/// [PROPOSAL] pays from a minted coin
public struct PayProposal() has drop;

/// [ACTION] mint new coins
public struct MintAction<phantom C: drop> has store {
    amount: u64,
}
/// [ACTION] burns coins
public struct BurnAction<phantom C: drop> has store {
    amount: u64,
}
/// [ACTION] updates a CoinMetadata object using a locked TreasuryCap 
public struct UpdateAction<phantom C: drop> has store { 
    name: Option<String>,
    symbol: Option<String>,
    description: Option<String>,
    icon_url: Option<String>,
}

// === [MEMBER] Public functions ===

/// Only a member can lock a TreasuryCap and borrow it.

public fun lock_cap<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    treasury_cap: TreasuryCap<C>,
    can_mint: bool,
) {
    auth.verify(account.addr());

    let treasury_lock = CurrencyLock { can_mint, treasury_cap };
    account.add_managed_asset(Do(), CurrencyKey<C> {}, treasury_lock);
}

public fun has_lock<Config, Outcome, C: drop>(
    account: &Account<Config, Outcome>
): bool {
    account.has_managed_asset(CurrencyKey<C> {})
}

public fun borrow_lock<Config, Outcome, C: drop>(
    account: &Account<Config, Outcome>
): &CurrencyLock<C> {
    account.borrow_managed_asset(Do(), CurrencyKey<C> {})
}

public fun borrow_lock_mut<Config, Outcome, C: drop>(
    account: &mut Account<Config, Outcome>
): &mut CurrencyLock<C> {
    account.borrow_managed_asset_mut(Do(), CurrencyKey<C> {})
}

public fun can_mint<C: drop>(lock: &CurrencyLock<C>): bool {
    lock.can_mint
}

public fun supply<C: drop>(lock: &CurrencyLock<C>): u64 {
    lock.treasury_cap.total_supply()
}

// === [PROPOSAL] Public functions ===

// step 1: propose to mint an amount of a coin that will be transferred to the Account
public fun propose_mint<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, C>(account), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        MintProposal(), 
        type_to_name<C>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );

    new_mint<Outcome, C, MintProposal>(
        &mut proposal, 
        borrow_lock<Config, Outcome, C>(account), 
        amount, 
        MintProposal()
    );
    account.add_proposal(proposal, MintProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: mint the coins and send them to the account
public fun execute_mint<Config, Outcome, C: drop>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    ctx: &mut TxContext
) {
    let coin = mint<Config, Outcome, C, MintProposal>(&mut executable, account, MintProposal(), ctx);
    transfer::public_transfer(coin, account.addr());

    destroy_mint<C, MintProposal>(&mut executable, MintProposal());
    executable.destroy(MintProposal());
}

// step 1: propose to burn an amount of a coin owned by the account
public fun propose_burn<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_id: ID,
    amount: u64,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, C>(account), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        BurnProposal(), 
        type_to_name<C>(), // the coin type is the auth name 
        key, 
        description, 
        execution_time, 
        expiration_epoch, 
        ctx
    );

    owned::new_withdraw(&mut proposal, vector[coin_id], BurnProposal());
    new_burn<Outcome, C, BurnProposal>(&mut proposal, amount, BurnProposal());

    account.add_proposal(proposal, BurnProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: burn the coin initially owned by the account
public fun execute_burn<Config, Outcome, C: drop>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    receiving: Receiving<Coin<C>>,
) {
    let coin = owned::withdraw(&mut executable, account, receiving, BurnProposal());
    burn<Config, Outcome, C, BurnProposal>(&mut executable, account, coin, BurnProposal());

    owned::destroy_withdraw(&mut executable, BurnProposal());
    destroy_burn<C, BurnProposal>(&mut executable, BurnProposal());
    executable.destroy(BurnProposal());
}

// step 1: propose to update the CoinMetadata
public fun propose_update<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    md_name: Option<String>,
    md_symbol: Option<String>,
    md_description: Option<String>,
    md_icon: Option<String>,
    ctx: &mut TxContext
) {
    assert!(has_lock<Config, Outcome, C>(account), ENoLock);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        UpdateProposal(),
        type_to_name<C>(), // the coin type is the auth name 
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_update<Outcome, C, UpdateProposal>(
        &mut proposal, 
        md_name, 
        md_symbol, 
        md_description, 
        md_icon, 
        UpdateProposal()
    );
    account.add_proposal(proposal, UpdateProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (AccountConfig::module::execute_proposal)

// step 4: update the CoinMetadata
public fun execute_update<Config, Outcome, C: drop>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<C>,
) {
    update(&mut executable, account, metadata, UpdateProposal());

    destroy_update<C, UpdateProposal>(&mut executable, UpdateProposal());
    executable.destroy(UpdateProposal());
}

// step 1: propose to send managed coins
public fun propose_transfer<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    amounts: vector<u64>,
    recipients: vector<address>,
    ctx: &mut TxContext
) {
    assert!(amounts.length() == recipients.length(), EDifferentLength);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        TransferProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    amounts.zip_do!(recipients, |amount, recipient| {
        new_mint<Outcome, C, TransferProposal>(
            &mut proposal, 
            borrow_lock<Config, Outcome, C>(account), 
            amount, 
            TransferProposal()
        );
        transfers::new_transfer(&mut proposal, recipient, TransferProposal());
    });

    account.add_proposal(proposal, TransferProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over transfer
public fun execute_transfer<Config, Outcome, C: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = mint(executable, account, TransferProposal(), ctx);

    let mut is_executed = false;
    let mint: &MintAction<C> = executable.action();

    if (mint.amount == 0) {
        let MintAction<C> { .. } = executable.remove_action(TransferProposal());
        is_executed = true;
    };

    transfers::transfer(executable, account, coin, TransferProposal(), is_executed);

    if (is_executed) {
        transfers::destroy_transfer(executable, TransferProposal());
    }
}

// step 1: propose to pay from a minted coin
public fun propose_pay<Config, Outcome, C: drop>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    coin_amount: u64,
    amount: u64, // amount to be paid at each interval
    interval: u64, // number of epochs between each payment
    recipient: address,
    ctx: &mut TxContext
) {
    let mut proposal = account.create_proposal(
        auth,
        outcome,
        PayProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );

    new_mint<Outcome, C, PayProposal>(
        &mut proposal, 
        borrow_lock<Config, Outcome, C>(account), 
        coin_amount, 
        PayProposal()
    );
    payments::new_pay(&mut proposal, amount, interval, recipient, PayProposal());

    account.add_proposal(proposal, PayProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: loop over it in PTB, sends last object from the Send action
public fun execute_pay<Config, Outcome, C: drop>(
    mut executable: Executable, 
    account: &mut Account<Config, Outcome>, 
    ctx: &mut TxContext
) {
    let coin: Coin<C> = mint(&mut executable, account, PayProposal(), ctx);
    payments::pay(&mut executable, account, coin, PayProposal(), ctx);

    destroy_mint<C, PayProposal>(&mut executable, PayProposal());
    payments::destroy_pay(&mut executable, PayProposal());
    executable.destroy(PayProposal());
}

// === [ACTION] Public functions ===

public fun new_mint<Outcome, C: drop, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    lock: &CurrencyLock<C>,
    amount: u64,
    witness: W,    
) {
    assert!(lock.can_mint, EMintDisabled);
    proposal.add_action(MintAction<C> { amount }, witness);
}

public fun mint<Config, Outcome, C: drop, W: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    witness: W, 
    ctx: &mut TxContext
): Coin<C> {
    let mint_mut: &mut MintAction<C> = executable.action_mut(account.addr(), witness);
    
    let lock_mut = borrow_lock_mut<Config, Outcome, C>(account);
    let coin = lock_mut.treasury_cap.mint(mint_mut.amount, ctx);
    mint_mut.amount = 0; // reset to ensure it has been executed
    coin
}

public fun destroy_mint<C: drop, W: drop>(executable: &mut Executable, witness: W) {
    let MintAction<C> { amount } = executable.remove_action(witness);
    assert!(amount == 0, EMintNotExecuted);
}

public fun delete_mint_action<Outcome, C: drop>(expired: Expired<Outcome>) {
    let MintAction<C> { .. } = expired.remove_expired_action();
}

public fun new_burn<Outcome, C: drop, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    amount: u64, 
    witness: W
) {
    proposal.add_action(BurnAction<C> { amount }, witness);
}

public fun burn<Config, Outcome, C: drop, W: drop>(
    executable: &mut Executable, 
    account: &mut Account<Config, Outcome>,
    coin: Coin<C>,
    witness: W, 
) {
    let burn_mut: &mut BurnAction<C> = executable.action_mut(account.addr(), witness);
    
    let lock_mut = borrow_lock_mut<Config, Outcome, C>(account);
    assert!(burn_mut.amount == coin.value(), EWrongValue);
    lock_mut.treasury_cap.burn(coin);
    burn_mut.amount = 0; // reset to ensure it has been executed
}

public fun destroy_burn<C: drop, W: drop>(executable: &mut Executable, witness: W) {
    let BurnAction<C> { amount } = executable.remove_action(witness);
    assert!(amount == 0, EBurnNotExecuted);
}

public fun delete_burn_action<Outcome, C: drop>(expired: Expired<Outcome>) {
    let BurnAction<C> { .. } = expired.remove_expired_action();
}

public fun new_update<Outcome, C: drop, W: drop>(
    proposal: &mut Proposal<Outcome>,
    name: Option<String>,
    symbol: Option<String>,
    description: Option<String>,
    icon_url: Option<String>,
    witness: W,
) {
    assert!(name.is_some() || symbol.is_some() || description.is_some() || icon_url.is_some(), ENoChange);
    proposal.add_action(UpdateAction<C> { name, symbol, description, icon_url }, witness);
}

public fun update<Config, Outcome, C: drop, W: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    metadata: &mut CoinMetadata<C>,
    witness: W,
) {
    let update_mut: &mut UpdateAction<C> = executable.action_mut(account.addr(), witness);
    let lock_mut = borrow_lock_mut<Config, Outcome, C>(account);

    if (update_mut.name.is_some()) {
        lock_mut.treasury_cap.update_name(metadata, update_mut.name.extract());
    };
    if (update_mut.symbol.is_some()) {
        lock_mut.treasury_cap.update_symbol(metadata, string::to_ascii(update_mut.symbol.extract()));
    };
    if (update_mut.description.is_some()) {
        lock_mut.treasury_cap.update_description(metadata, update_mut.description.extract());
    };
    if (update_mut.icon_url.is_some()) {
        lock_mut.treasury_cap.update_icon_url(metadata, string::to_ascii(update_mut.icon_url.extract()));
    };
    // all fields are set to none now
}

public fun destroy_update<C: drop, W: drop>(executable: &mut Executable, witness: W) {
    let UpdateAction<C> { name, symbol, description, icon_url, .. } = executable.remove_action(witness);
    assert!(name.is_none() && symbol.is_none() && description.is_none() && icon_url.is_none(), EUpdateNotExecuted);
}

public fun delete_update_action<Outcome, C: drop>(expired: Expired<Outcome>) {
    let UpdateAction<C> { .. } = expired.remove_expired_action();
}


// === Private functions ===

fun type_to_name<T: drop>(): String {
    type_name::get<T>().into_string().to_string()
}
