/// This is the core module managing Proposals.
/// It provides the interface to create, approve and execute proposals which is used in the `account` module.

module account_protocol::proposals;

// === Imports ===

use std::string::String;
use sui::{
    bag::{Self, Bag},
    clock::Clock,
};
use account_protocol::{
    source::Source,
};

// === Errors ===

const ECantBeExecutedYet: u64 = 0;
const EHasntExpired: u64 = 1;
const EProposalNotFound: u64 = 2;
const EProposalKeyAlreadyExists: u64 = 3;

// === Structs ===

/// Parent struct protecting the proposals
public struct Proposals<Outcome> has store {
    inner: vector<Proposal<Outcome>>
}

/// Child struct, proposal owning a sequence of actions requested to be executed
/// Outcome is a custom struct depending on the config
/// can be executed if total_weight >= account.thresholds.global
/// or role_weight >= account.thresholds.role
public struct Proposal<Outcome> has store {
    // module that issued the proposal and must destroy it
    source: Source,
    // name of the proposal, serves as a key, should be unique
    key: String,
    // what this proposal aims to do, for informational purpose
    description: String,
    // the proposal can be deleted from this epoch
    expiration_epoch: u64,
    // proposer can add a timestamp_ms before which the proposal can't be executed
    // can be used to schedule actions via a backend
    execution_time: u64,
    // heterogenous array of actions to be executed from last to first
    actions: Bag,
    // Generic struct storing vote related data, depends on the config
    outcome: Outcome
}

/// Hot potato wrapping actions and outcome from a proposal that expired
public struct Expired<Outcome> {
    actions: Bag,
    next_to_destroy: u64,
    outcome: Outcome,
}

// === View functions ===

public fun length<Outcome>(proposals: &Proposals<Outcome>): u64 {
    proposals.inner.length()
}

public fun contains<Outcome>(proposals: &Proposals<Outcome>, key: String): bool {
    proposals.inner.any!(|proposal| proposal.key == key)
}

public fun get_idx<Outcome>(proposals: &Proposals<Outcome>, key: String): u64 {
    proposals.inner.find_index!(|proposal| proposal.key == key).destroy_some()
}

public fun get<Outcome>(proposals: &Proposals<Outcome>, key: String): &Proposal<Outcome> {
    assert!(proposals.contains(key), EProposalNotFound);
    let idx = proposals.get_idx(key);
    &proposals.inner[idx]
}

public fun source<Outcome>(proposal: &Proposal<Outcome>): &Source {
    &proposal.source
}

public fun description<Outcome>(proposal: &Proposal<Outcome>): String {
    proposal.description
}

public fun expiration_epoch<Outcome>(proposal: &Proposal<Outcome>): u64 {
    proposal.expiration_epoch
}

public fun execution_time<Outcome>(proposal: &Proposal<Outcome>): u64 {
    proposal.execution_time
}

public fun actions_length<Outcome>(proposal: &Proposal<Outcome>): u64 {
    proposal.actions.length()
}

public fun outcome<Outcome>(proposal: &Proposal<Outcome>): &Outcome {
    &proposal.outcome
}

// === Proposal functions ===

/// Inserts an action to the proposal bag
public fun add_action<Outcome, A: store, W: drop>(
    proposal: &mut Proposal<Outcome>, 
    action: A, 
    witness: W
) {
    // ensures the function is called within the same proposal as the one that created Proposal
    proposal.source().assert_is_constructor(witness);

    let idx = proposal.actions.length();
    proposal.actions.add(idx, action);
}

// === Package functions ===

/// The following functions are only used in the `account` module

public(package) fun empty<Outcome>(): Proposals<Outcome> {
    Proposals<Outcome> { inner: vector[] }
}

public(package) fun new_proposal<Outcome>(
    source: Source,
    key: String,
    description: String,
    execution_time: u64, // timestamp in ms
    expiration_epoch: u64,
    outcome: Outcome,
    ctx: &mut TxContext
): Proposal<Outcome> {
    Proposal<Outcome> { 
        source,
        key,
        description,
        execution_time,
        expiration_epoch,
        actions: bag::new(ctx),
        outcome
    }
}

public(package) fun add<Outcome>(
    proposals: &mut Proposals<Outcome>,
    proposal: Proposal<Outcome>,
) {
    assert!(!proposals.contains(proposal.key), EProposalKeyAlreadyExists);
    proposals.inner.push_back(proposal);
}

/// Removes an proposal being executed if the execution_time is reached
/// Outcome must be validated in AccountConfig to be destroyed
public(package) fun remove<Outcome>(
    proposals: &mut Proposals<Outcome>,
    key: String,
    clock: &Clock,
): (Source, Bag, Outcome) {
    let idx = proposals.get_idx(key);
    let Proposal { execution_time, source, actions, outcome, .. } = proposals.inner.remove(idx);
    assert!(clock.timestamp_ms() >= execution_time, ECantBeExecutedYet);

    (source, actions, outcome)
}

public(package) fun get_mut<Outcome>(proposals: &mut Proposals<Outcome>, key: String): &mut Proposal<Outcome> {
    assert!(proposals.contains(key), EProposalNotFound);
    let idx = proposals.get_idx(key);
    &mut proposals.inner[idx]
}

public(package) fun outcome_mut<Outcome>(proposal: &mut Proposal<Outcome>): &mut Outcome {
    &mut proposal.outcome
}

public(package) fun delete<Outcome>(
    proposals: &mut Proposals<Outcome>,
    key: String,
    ctx: &TxContext
): (Source, Expired<Outcome>) {
    let idx = proposals.get_idx(key);
    let Proposal<Outcome> { source, expiration_epoch, actions, outcome, .. } = proposals.inner.remove(idx);
    assert!(expiration_epoch <= ctx.epoch(), EHasntExpired);

    (source, Expired { actions, next_to_destroy: 0, outcome })
}

/// After calling `account::delete_proposal`, delete each action in its own module
public fun remove_expired_action<Outcome, A: store>(expired: &mut Expired<Outcome>) : A {
    let action = expired.actions.remove(expired.next_to_destroy);
    expired.next_to_destroy = expired.next_to_destroy + 1;
    
    action
}

/// When the actions bag is empty, call this function from the right AccountConfig module
public fun remove_expired_outcome<Outcome>(expired: Expired<Outcome>) : Outcome {
    let Expired { actions, outcome, .. } = expired;
    actions.destroy_empty();

    outcome
}