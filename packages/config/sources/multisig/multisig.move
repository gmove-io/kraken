
module account_config::multisig;

// === Imports ===

use std::string::String;
use sui::{
    vec_set::{Self, VecSet},
    vec_map::{Self, VecMap},
    clock::Clock,
};
use account_extensions::extensions::Extensions;
use account_protocol::{
    account::{Self, Account},
    executable::Executable,
    proposals::Expired,
    source::Source,
    auth::{Self, Auth},
};

// === Errors ===

const EMemberNotFound: u64 = 0;
const ECallerIsNotMember: u64 = 1;
const ERoleNotFound: u64 = 2;
const EThresholdNotReached: u64 = 3;
const ENotApproved: u64 = 4;
const ERoleDoesntExist: u64 = 5;
const EThresholdTooHigh: u64 = 6;
const EThresholdNull: u64 = 7;
const EMembersNotSameLength: u64 = 8;
const ERolesNotSameLength: u64 = 9;
const EAlreadyApproved: u64 = 10;

// === Events ===

// public struct Created has copy, drop, store {
//     auth_witness: String,
//     auth_name: String,
//     key: String,
//     description: String,
// }

// public struct Approved has copy, drop, store {
//     auth_witness: String,
//     auth_name: String,
//     key: String,
//     description: String,
// }

// public struct Executed has copy, drop, store {
//     auth_witness: String,
//     auth_name: String,
//     key: String,
//     description: String,
// }

// === Structs ===

/// [MEMBER] interacts with proposal
public struct Do() has drop;
/// [PROPOSAL] modifies the members and thresholds of the account
public struct ConfigMultisigProposal() has drop;

/// [ACTION] wraps a Multisig struct into an action
public struct ConfigMultisigAction has store {
    config: Multisig,
}

/// Parent struct protecting the config
public struct Multisig has copy, drop, store {
    // members and associated data
    members: vector<Member>,
    // global threshold
    global: u64,
    // role name with role threshold
    roles: vector<Role>,
}

/// Child struct for managing and displaying members
public struct Member has copy, drop, store {
    addr: address,
    // voting power of the member
    weight: u64,
    // ID of the member's User object, none if he didn't join yet
    user_id: Option<ID>,
    // roles that have been attributed
    roles: VecSet<String>,
}

/// Child struct representing a role with a name and its threshold
public struct Role has copy, drop, store {
    // role name: witness + optional name
    name: String,
    // threshold for the role
    threshold: u64,
}

/// Outcome field for the Proposals, must be validated before destruction
public struct Approvals has store {
    // total weight of all members that approved the proposal
    total_weight: u64,
    // sum of the weights of members who approved and have the role
    role_weight: u64, 
    // who has approved the proposal
    approved: VecSet<address>,
}

// === Public functions ===

/// Init and returns a new Account object
/// Creator is added by default with weight and global threshold of 1
public fun new_account(
    extensions: &Extensions,
    name: String,
    account_id: ID,
    ctx: &mut TxContext,
): Account<Multisig, Approvals> {
    let config = Multisig {
        members: vector[Member { 
            addr: ctx.sender(), 
            weight: 1, 
            user_id: option::some(account_id), 
            roles: vec_set::empty() 
        }],
        global: 1,
        roles: vector[],
    };

    account::new(extensions, name, config, ctx)
}

/// Creates a new outcome to initiate a proposal
public fun new_outcome(
    account: &Account<Multisig, Approvals>,
    ctx: &TxContext
): Approvals {
    account.config().assert_is_member(ctx);

    Approvals {
        total_weight: 0,
        role_weight: 0,
        approved: vec_set::empty(),
    }
}

/// Authenticates the caller for a given role or globally
public fun authenticate(
    extensions: &Extensions,
    account: &Account<Multisig, Approvals>,
    role: String, // can be empty
    ctx: &TxContext
): Auth {
    account.config().assert_is_member(ctx);

    auth::new(extensions, role, account.addr(), Do())
}

public fun approve_proposal(
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    ctx: &TxContext
) {
    assert!(
        !account.proposal(key).outcome().approved.contains(&ctx.sender()), 
        EAlreadyApproved
    );

    let role = account.proposal(key).source().full_role();
    let member = account.config().get_member(ctx.sender());
    let has_role = member.has_role(role);

    let outcome_mut = account.outcome_mut(key, Do());
    outcome_mut.approved.insert(ctx.sender()); // throws if already approved
    outcome_mut.total_weight = outcome_mut.total_weight + member.weight;
    if (has_role)
        outcome_mut.role_weight = outcome_mut.role_weight + member.weight;
}

public fun disapprove_proposal(
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    ctx: &TxContext
) {
    assert!(
        account.proposal(key).outcome().approved.contains(&ctx.sender()), 
        ENotApproved
    );
    
    let role = account.proposal(key).source().full_role();
    let member = account.config().get_member(ctx.sender());
    let has_role = member.has_role(role);

    let outcome_mut = account.outcome_mut(key, Do());
    outcome_mut.approved.remove(&ctx.sender()); // throws if already approved
    outcome_mut.total_weight = outcome_mut.total_weight - member.weight;
    if (has_role)
        outcome_mut.role_weight = outcome_mut.role_weight - member.weight;
}

/// Returns an executable if the number of signers is >= (global || role) threshold
/// Anyone can execute a proposal, this allows to automate the execution of proposals
public fun execute_proposal(
    account: &mut Account<Multisig, Approvals>, 
    key: String, 
    clock: &Clock,
): Executable {
    let (executable, outcome) = account.execute_proposal(key, clock, Do());
    // account.deps().assert_version(&source, VERSION);
    outcome.validate(account.config(), executable.source());

    executable
}

// === [PROPOSAL] Public functions ===

/// No actions are defined as changing the config isn't supposed to be composable for security reasons

// step 1: propose to modify account rules (everything touching weights)
// threshold has to be valid (reachable and different from 0 for global)
public fun propose_config_multisig(
    extensions: &Extensions,
    account: &mut Account<Multisig, Approvals>, 
    key: String,
    description: String,
    execution_time: u64,
    expiration_epoch: u64,
    // members 
    addresses: vector<address>,
    weights: vector<u64>,
    mut roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
    ctx: &mut TxContext
) {
    // verify new rules are valid
    verify_new_rules(addresses, weights, roles, global, role_names, role_thresholds);
    // create outcome and auth
    let auth = authenticate(extensions, account, b"".to_string(), ctx);
    let outcome = new_outcome(account, ctx);

    let mut proposal = account.create_proposal(
        auth,
        outcome,
        ConfigMultisigProposal(),
        b"".to_string(),
        key,
        description,
        execution_time,
        expiration_epoch,
        ctx
    );
    // must modify members before modifying thresholds to ensure they are reachable

    let mut config = Multisig { members: vector[], global: 0, roles: vector[] };
    addresses.zip_do!(weights, |addr, weight| {
        config.members.push_back(Member {
            addr,
            weight,
            user_id: option::none(),
            roles: vec_set::from_keys(roles.remove(0)),
        });
    });

    config.global = global;
    role_names.zip_do!(role_thresholds, |role, threshold| {
        config.roles.push_back(Role { name: role, threshold });
    });

    proposal.add_action(ConfigMultisigAction { config }, ConfigMultisigProposal());
    account.add_proposal(proposal, ConfigMultisigProposal());
}

// step 2: multiple members have to approve the proposal (account::approve_proposal)

// step 3: execute the action and modify Account Multisig
public fun execute_config_multisig(
    mut executable: Executable,
    account: &mut Account<Multisig, Approvals>, 
) {
    let ConfigMultisigAction { config } = executable.remove_action(ConfigMultisigProposal());
    *account.config_mut(ConfigMultisigProposal()) = config;
    executable.destroy(ConfigMultisigProposal());
}

public fun delete_config_multisig_action(expired: &mut Expired<Approvals>) {
    let action = expired.remove_expired_action();
    let ConfigMultisigAction { .. } = action;
}

// === Accessors ===

/// Registers the member's User ID, upon joining the Account
public fun register_user_id(
    member: &mut Member,
    id: ID,
) {
    member.user_id.swap_or_fill(id);
}

/// Unregisters the member's User ID, upon leaving the Account
public fun unregister_user_id(
    member: &mut Member,
): ID {
    member.user_id.extract()
}

public fun addresses(multisig: &Multisig): vector<address> {
    multisig.members.map_ref!(|member| member.addr)
}

public fun get_member(multisig: &Multisig, addr: address): Member {
    let idx = multisig.get_member_idx(addr);
    multisig.members[idx]
}

public fun get_member_mut(multisig: &mut Multisig, addr: address): &mut Member {
    let idx = multisig.get_member_idx(addr);
    &mut multisig.members[idx]
}

public fun get_member_idx(multisig: &Multisig, addr: address): u64 {
    let opt = multisig.members.find_index!(|member| member.addr == addr);
    assert!(opt.is_some(), EMemberNotFound);
    opt.destroy_some()
}

public fun is_member(multisig: &Multisig, addr: address): bool {
    multisig.members.any!(|member| member.addr == addr)
}

public fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
    assert!(multisig.is_member(ctx.sender()), ECallerIsNotMember);
}

// // member functions
public fun weight(member: &Member): u64 {
    member.weight
}

public fun user_id(member: &Member): Option<ID> {
    member.user_id
}

public fun roles(member: &Member): vector<String> {
    *member.roles.keys()
}

public fun has_role(member: &Member, role: String): bool {
    member.roles.contains(&role)
}

// // roles functions

public fun get_global_threshold(multisig: &Multisig): u64 {
    multisig.global
}

public fun get_role_threshold(multisig: &Multisig, name: String): u64 {
    let idx = multisig.get_role_idx(name);
    multisig.roles[idx].threshold
}

public fun get_role_idx(multisig: &Multisig, name: String): u64 {
    let opt = multisig.roles.find_index!(|role| role.name == name);
    assert!(opt.is_some(), ERoleNotFound);
    opt.destroy_some()
}

public fun role_exists(multisig: &Multisig, name: String): bool {
    multisig.roles.any!(|role| role.name == name)
}

// === Private functions ===

fun verify_new_rules(
    // members 
    addresses: vector<address>,
    weights: vector<u64>,
    roles: vector<vector<String>>,
    // thresholds 
    global: u64,
    role_names: vector<String>,
    role_thresholds: vector<u64>,
) {
    let total_weight = weights.fold!(0, |acc, weight| acc + weight);    
    assert!(addresses.length() == weights.length() && addresses.length() == roles.length(), EMembersNotSameLength);
    assert!(role_names.length() == role_thresholds.length(), ERolesNotSameLength);
    assert!(total_weight >= global, EThresholdTooHigh);
    assert!(global != 0, EThresholdNull);

    let mut weights_for_role: VecMap<String, u64> = vec_map::empty();
    weights.zip_do!(roles, |weight, roles_for_addr| {
        roles_for_addr.do!(|role| {
            if (weights_for_role.contains(&role)) {
                *weights_for_role.get_mut(&role) = weight;
            } else {
                weights_for_role.insert(role, weight);
            }
        });
    });

    while (!weights_for_role.is_empty()) {
        let (role, weight) = weights_for_role.pop();
        let (role_exists, idx) = role_names.index_of(&role);
        assert!(role_exists, ERoleDoesntExist);
        assert!(weight >= role_thresholds[idx], EThresholdTooHigh);
    };
}

fun validate(
    outcome: Approvals, 
    multisig: &Multisig, 
    source: &Source,
) {
    let Approvals { total_weight, role_weight, .. } = outcome;
    let role = source.full_role();

    assert!(
        total_weight >= multisig.global ||
        (multisig.role_exists(role) && role_weight >= multisig.get_role_threshold(role)), 
        EThresholdNotReached
    );
}

// === Test functions ===

// #[test_only]
// public fun remove(
//     multisig: &mut Multisig,
//     addr: address,
// ) {
//     let idx = multisig.get_member_idx(addr);
//     multisig.members.remove(idx);
// }

// #[test_only]
// public fun set_weight(
//     member: &mut Member,
//     weight: u64,
// ) {
//     member.weight = weight;
// }

// #[test_only]
// public fun add_roles(
//     member: &mut Member,
//     roles: vector<String>,
// ) {
//     roles.do!(|role| {
//         member.roles.insert(role);
//     });
// }

// #[test_only]
// public fun remove_roles(
//     member: &mut Member,
//     roles: vector<String>,
// ) {
//     roles.do!(|role| {
//         member.roles.remove(&role);
//     });
// }

