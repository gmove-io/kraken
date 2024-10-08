/// Package managers can lock UpgradeCaps in the account. Caps can't be unlocked, this is to enforce the policies.
/// Any rule can be defined for the upgrade lock. The module provide a timelock rule by default, based on execution time.
/// Upon locking, the user can define an optional timelock corresponding to the minimum delay between an upgrade proposal and its execution.
/// The account can decide to make the policy more restrictive or destroy the Cap, to make the package immutable.

module account_actions::upgrade_policies;

// === Imports ===

use std::string::String;
use sui::{
    package::{Self, UpgradeCap, UpgradeTicket, UpgradeReceipt},
    clock::Clock,
    dynamic_field as df,
    event,
};
use account_protocol::{
    account::Account,
    proposals::{Proposal, Expired},
    executable::Executable,
    auth::Auth,
};

// === Error ===

const EPolicyShouldRestrict: u64 = 1;
const EInvalidPolicy: u64 = 2;
const EUpgradeNotExecuted: u64 = 3;
const ERestrictNotExecuted: u64 = 4;
const ENoLock: u64 = 5;

// === Events ===

public struct Upgraded has copy, drop, store {
    package_id: ID,
    digest: vector<u8>,
}

public struct Restricted has copy, drop, store {
    package_id: ID,
    policy: u8,
}

// === Structs ===

/// Dynamic field key for the UpgradeLock
public struct UpgradeKey has copy, drop, store { name: String }

/// Dynamic field wrapper restricting access to an UpgradeCap, with optional timelock
public struct UpgradeLock has key, store {
    id: UID,
    // the cap to lock
    upgrade_cap: UpgradeCap,
    // each package can define its own config
    // DF: config: C,
}

/// Dynamic field key for TimeLock
public struct TimeLockKey has copy, drop, store {}

/// Dynamic field timelock config for the UpgradeLock
public struct TimeLock has store {
    delay_ms: u64,
}

/// [MEMBER] can lock an UpgradeCap and borrow it
public struct ManageUpgrades has copy, drop {}
/// [PROPOSAL] upgrades a package
public struct UpgradeProposal has copy, drop {}
/// [PROPOSAL] restricts a locked UpgradeCap
public struct RestrictProposal has copy, drop {}

/// [ACTION] upgrades a package
public struct UpgradeAction has store {
    // digest of the package build we want to publish
    digest: vector<u8>,
}

/// [ACTION] restricts a locked UpgradeCap
public struct RestrictAction has store {
    // downgrades to this policy
    policy: u8,
}

// === [MEMBER] Public Functions ===

/// Creates a new UpgradeLock and returns it
public fun new_lock(
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
): UpgradeLock {
    UpgradeLock { 
        id: object::new(ctx),
        upgrade_cap 
    }
}

/// Adds a rule with any config to the upgrade lock
public fun add_rule<K: copy + drop + store, R: store>(
    lock: &mut UpgradeLock,
    key: K,
    rule: R,
) {
    df::add(&mut lock.id, key, rule);
}

/// Checks if a rule exists
public fun has_rule<K: copy + drop + store>(
    lock: &UpgradeLock,
    key: K,
): bool {
    df::exists_(&lock.id, key)
}

/// Attaches the UpgradeLock as a Dynamic Field to the account
public fun lock_cap<Config, Outcome>(
    auth: Auth,
    lock: UpgradeLock,
    account: &mut Account<Config, Outcome>,
    name: String,
) {
    auth.verify(account.addr());
    account.add_managed_asset(ManageUpgrades {}, UpgradeKey { name }, lock);
}

/// Locks a cap with a timelock rule
public fun lock_cap_with_timelock<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>,
    name: String,
    delay_ms: u64,
    upgrade_cap: UpgradeCap,
    ctx: &mut TxContext
) {
    let mut lock = new_lock(upgrade_cap, ctx);
    add_rule(&mut lock, TimeLockKey {}, TimeLock { delay_ms });
    lock_cap(auth, lock, account, name);
}

public fun has_lock<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    name: String
): bool {
    account.has_managed_asset(UpgradeKey { name })
}

public fun borrow_lock<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    name: String
): &UpgradeLock {
    account.borrow_managed_asset(ManageUpgrades {}, UpgradeKey { name })
}

public fun borrow_lock_mut<Config, Outcome>(
    account: &mut Account<Config, Outcome>, 
    name: String
): &mut UpgradeLock {
    account.borrow_managed_asset_mut(ManageUpgrades {}, UpgradeKey { name })
}

public fun upgrade_cap(lock: &UpgradeLock): &UpgradeCap {
    &lock.upgrade_cap
} 

// === [PROPOSAL] Public Functions ===

// step 1: propose an UpgradeAction by passing the digest of the package build
// execution_time is automatically set to now + timelock
// if timelock = 0, it means that upgrade can be executed at any time
public fun propose_upgrade<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    expiration_epoch: u64,
    name: String,
    digest: vector<u8>,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, name), ENoLock);
    let lock = borrow_lock(account, name);
    let delay = lock.time_delay();

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        UpgradeProposal {},
        name,
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_epoch,
        ctx
    );

    new_upgrade(&mut proposal, digest, UpgradeProposal {});
    account.add_proposal(proposal, UpgradeProposal {});
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: destroy UpgradeAction and return the UpgradeTicket for upgrading
public fun execute_upgrade<Config, Outcome>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
): UpgradeTicket {
    upgrade(executable, account, UpgradeProposal {})
}    

// step 5: consume the ticket to upgrade  

// step 6: consume the receipt to commit the upgrade
public fun confirm_upgrade<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
    receipt: UpgradeReceipt,
) {
    let name = executable.source().role_name();
    let lock_mut = borrow_lock_mut(account, name);
    package::commit_upgrade(&mut lock_mut.upgrade_cap, receipt);
    
    destroy_upgrade(&mut executable, UpgradeProposal {});
    executable.destroy(UpgradeProposal {});
}

// step 1: propose an UpgradeAction by passing the digest of the package build
// execution_time is automatically set to now + timelock
public fun propose_restrict<Config, Outcome>(
    auth: Auth,
    account: &mut Account<Config, Outcome>, 
    outcome: Outcome,
    key: String,
    description: String,
    expiration_epoch: u64,
    name: String,
    policy: u8,
    clock: &Clock,
    ctx: &mut TxContext
) {
    assert!(has_lock(account, name), ENoLock);
    let lock = borrow_lock(account, name);
    let delay = lock.time_delay();
    let current_policy = lock.upgrade_cap.policy();

    let mut proposal = account.create_proposal(
        auth, 
        outcome,
        RestrictProposal {},
        name,
        key,
        description,
        clock.timestamp_ms() + delay,
        expiration_epoch,
        ctx
    );

    new_restrict(&mut proposal, current_policy, policy, RestrictProposal {});
    account.add_proposal(proposal, RestrictProposal {});
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)
// step 3: execute the proposal and return the action (account::execute_proposal)

// step 4: restrict the upgrade policy
public fun execute_restrict<Config, Outcome>(
    mut executable: Executable,
    account: &mut Account<Config, Outcome>,
) {
    restrict(&mut executable, account, RestrictProposal {});
    destroy_restrict(&mut executable, RestrictProposal {});
    executable.destroy(RestrictProposal {});
}

// [ACTION] Public Functions ===

public fun new_upgrade<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    digest: vector<u8>, 
    witness: W
) {
    proposal.add_action(UpgradeAction { digest }, witness);
}    

public fun upgrade<Config, Outcome, W: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    witness: W,
): UpgradeTicket {
    let name = executable.source().role_name();
    let upgrade_mut: &mut UpgradeAction = executable.action_mut(account.addr(), witness);
    let lock_mut = borrow_lock_mut(account, name);

    event::emit(Upgraded {
        package_id: lock_mut.upgrade_cap.package(),
        digest: upgrade_mut.digest,
    });

    let policy = lock_mut.upgrade_cap.policy();
    let ticket = lock_mut.upgrade_cap.authorize_upgrade(policy, upgrade_mut.digest);
    // consume digest to ensure this function has been called exactly once
    upgrade_mut.digest = vector::empty();

    ticket
}    

public fun destroy_upgrade<W: drop>(executable: &mut Executable, witness: W) {
    let UpgradeAction { digest, .. } = executable.remove_action(witness);
    assert!(digest.is_empty(), EUpgradeNotExecuted);
}

public fun new_restrict<Outcome, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    current_policy: u8, 
    policy: u8, 
    witness: W
) {    
    assert!(policy > current_policy, EPolicyShouldRestrict);
    assert!(
        policy == package::additive_policy() ||
        policy == package::dep_only_policy() ||
        policy == 255, // make immutable
        EInvalidPolicy
    );

    proposal.add_action(RestrictAction { policy }, witness);
}    

public fun restrict<Config, Outcome, W: drop>(
    executable: &mut Executable,
    account: &mut Account<Config, Outcome>,
    witness: W,
) {
    let name = executable.source().role_name();
    let restrict_mut: &mut RestrictAction = executable.action_mut(account.addr(), witness);

    let (package_id, policy) = if (restrict_mut.policy == package::additive_policy()) {
        let lock_mut: &mut UpgradeLock = account.borrow_managed_asset_mut(ManageUpgrades {}, UpgradeKey { name });
        lock_mut.upgrade_cap.only_additive_upgrades();
        (lock_mut.upgrade_cap.package(), restrict_mut.policy)
    } else if (restrict_mut.policy == package::dep_only_policy()) {
        let lock_mut: &mut UpgradeLock = account.borrow_managed_asset_mut(ManageUpgrades {}, UpgradeKey { name });
        lock_mut.upgrade_cap.only_dep_upgrades();
        (lock_mut.upgrade_cap.package(), restrict_mut.policy)
    } else {
        let lock: UpgradeLock = account.remove_managed_asset(ManageUpgrades {}, UpgradeKey { name });
        let (package_id, policy) = (lock.upgrade_cap.package(), restrict_mut.policy);
        let UpgradeLock { id, upgrade_cap } = lock;
        package::make_immutable(upgrade_cap);
        id.delete();
        (package_id, policy)
    };

    event::emit(Restricted {
        package_id,
        policy,
    });
    // consume policy to ensure this function has been called exactly once
    restrict_mut.policy = 0;
}

public fun destroy_restrict<W: drop>(executable: &mut Executable, witness: W) {
    let RestrictAction { policy, .. } = executable.remove_action(witness);
    assert!(policy == 0, ERestrictNotExecuted);
}

public fun delete_upgrade_action<Outcome>(expired: Expired<Outcome>) {
    let UpgradeAction { .. } = expired.remove_expired_action();
}

// === Private Functions ===

fun time_delay(lock: &UpgradeLock): u64 {
    if (lock.has_rule(TimeLockKey {})) {
        let timelock: &TimeLock = df::borrow(&lock.id, TimeLockKey {});
        timelock.delay_ms
    } else {
        0
    }
}
