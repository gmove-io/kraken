/// Users have a non-transferable User account object used to track Accounts in which they are a member.
/// They can also set a username and profile picture to be displayed on the various frontends.
/// Account members can send on-chain invites to new members. 
/// Alternatively, multisig Account creators can share an invite link to new members that can join the Account without invite.
/// Invited users can accept or refuse the invite, to add the Account id to their User account or not.
/// This avoid the need for an indexer as all data can be easily found on-chain.

module kraken_account::user;

// === Imports ===

use std::string::String;
use sui::{
    vec_set::{Self, VecSet},
    table::{Self, Table},
};
use kraken_account::account::Account;

// === Errors ===

const ENotMember: u64 = 0;
const EWrongAccount: u64 = 1;
const EMustLeaveAllAccounts: u64 = 2;
const EAlreadyHasUser: u64 = 3;

// === Struct ===

/// Shared object enforcing one account maximum per user
public struct Registry has key {
    id: UID,
    // address to User mapping
    users: Table<address, ID>,
}

/// Non-transferable user account for tracking Accounts
public struct User has key {
    id: UID,
    // to display on the frontends
    username: String,
    // to display on the frontends
    profile_picture: String,
    // multisig accounts that the user has joined
    account_ids: VecSet<ID>,
}

/// Invite object issued by an Account to a user
public struct Invite has key { 
    id: UID, 
    // Account that issued the invite
    account_id: ID,
}

// === Public functions ===

fun init(ctx: &mut TxContext) {
    transfer::share_object(Registry {
        id: object::new(ctx),
        users: table::new(ctx),
    });
}

/// Creates a soulbound User account (1 per address)
public fun new(username: String, profile_picture: String, ctx: &mut TxContext): User {
    User {
        id: object::new(ctx),
        username,
        profile_picture,
        account_ids: vec_set::empty(),
    }
}

// === [MEMBER] Public functions ===

/// Fills user_id in Account, inserts account_id in User, aborts if already joined
public fun join_account(user: &mut User, account: &mut Account, ctx: &TxContext) {
    account.member_mut(ctx.sender()).register_user_id(user.id.to_inner());
    user.account_ids.insert(object::id(account)); 
}

/// Extracts and verifies user_id in Account, removes account_id from User, aborts if not member
public fun leave_account(user: &mut User, account: &mut Account, ctx: &TxContext) {
    account.member_mut(ctx.sender()).unregister_user_id();
    user.account_ids.remove(&object::id(account));
}

/// Can transfer the User object only if the other address has no User object yet
public fun transfer(registry: &mut Registry, user: User, recipient: address) {
    assert!(!registry.users.contains(recipient), EAlreadyHasUser);
    transfer::transfer(user, recipient);
}

/// Must leave all Accounts before, for consistency
public fun destroy(user: User) {
    let User { id, account_ids, .. } = user;
    assert!(account_ids.is_empty(), EMustLeaveAllAccounts);
    id.delete();
}

/// Invites can be sent by an Account member (upon Account creation for instance)
public fun send_invite(account: &Account, recipient: address, ctx: &mut TxContext) {
    // user inviting must be member
    account.assert_is_member(ctx);
    // invited user must be member
    assert!(account.members().is_member(recipient), ENotMember);
    let invite = Invite { 
        id: object::new(ctx), 
        account_id: object::id(account) 
    };
    transfer::transfer(invite, recipient);
}

/// Invited user can register the Account in his User account
public fun accept_invite(user: &mut User, account: &mut Account, invite: Invite, ctx: &TxContext) {
    let Invite { id, account_id } = invite;
    id.delete();
    assert!(account_id == object::id(account), EWrongAccount);
    user.join_account(account, ctx);
}

/// Deletes the invite object
public fun refuse_invite(invite: Invite) {
    let Invite { id, .. } = invite;
    id.delete();
}

// === View functions ===    

public fun username(user: &User): String {
    user.username
}

public fun profile_picture(user: &User): String {
    user.profile_picture
}

public fun account_ids(user: &User): vector<ID> {
    user.account_ids.into_keys()
}

public fun account_id(invite: &Invite): ID {
    invite.account_id
}

// === Test functions ===

#[test_only]
public fun init_for_testing(ctx: &mut TxContext) {
    init(ctx);
}