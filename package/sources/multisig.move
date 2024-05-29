/// This is the core module managing Multisig and Proposals.
/// Various actions to be executed by the Multisig can be attached to a Proposal.
/// The proposals have to be approved by at least the threshold number of members.

module kraken::multisig {
    use std::string::String;

    use sui::clock::Clock;
    use sui::dynamic_field as df;
    use sui::vec_set::{Self, VecSet};
    use sui::vec_map::{Self, VecMap};

    // === Errors ===

    const ECallerIsNotMember: u64 = 0;
    const EThresholdNotReached: u64 = 1;
    const EProposalNotEmpty: u64 = 2;
    const ECantBeExecutedYet: u64 = 3;

    // === Structs ===

    // shared object 
    public struct Multisig has key {
        id: UID,
        // human readable name to differentiate the multisigs
        name: String,
        // has to be always <= length(members)
        threshold: u64,
        // members of the multisig
        members: VecSet<address>,
        // open proposals, key should be a unique descriptive name
        proposals: VecMap<String, Proposal>,
    }

    // proposal owning a single action requested to be executed
    // can be executed if length(approved) >= multisig.threshold
    public struct Proposal has key, store {
        id: UID,
        // what this proposal aims to do, for informational purpose
        description: String,
        // the proposal can be deleted from this epoch
        expiration_epoch: u64,
        // proposer can add a timestamp_ms before which the proposal can't be executed
        // can be used to schedule actions via a backend
        execution_time: u64,
        // who has approved the proposal
        approved: VecSet<address>,
    }

    public struct Promise {
        multisig_addr: address,
        proposal_uid: UID,
    }

    // hot potato ensuring the action is executed as it can't be stored
    public struct Action<T: store> {
        inner: T,
    }

    // key for the inner action struct of a proposal
    public struct ActionKey has copy, drop, store {}
    // key for the inner object struct of a proposal
    public struct AccessKey has copy, drop, store {}

    // === Public mutative functions ===

    // init and share a new Multisig object
    public fun new(name: String, ctx: &mut TxContext): Multisig {
        Multisig { 
            id: object::new(ctx),
            name,
            threshold: 1,
            members: vec_set::singleton(ctx.sender()),
            proposals: vec_map::empty(),
        }
    }

    #[allow(lint(share_owned))]
    public fun share(multisig: Multisig) {
        transfer::share_object(multisig);
    }

    // anyone can clean expired proposals
    public fun clean_proposals(multisig: &mut Multisig, ctx: &mut TxContext) {
        let mut i = multisig.proposals.size();
        while (i > 0) {
            let (key, proposal) = multisig.proposals.get_entry_by_idx(i - 1);
            if (ctx.epoch() >= proposal.expiration_epoch) {
                let (_, proposal) = multisig.proposals.remove(&*key);
                let Proposal { 
                    id, 
                    description: _, 
                    expiration_epoch: _, 
                    execution_time: _, 
                    approved: _ 
                } = proposal;
                id.delete();
            };
            i = i - 1;
        } 
    }

    // === Multisig-only functions ===

    // create a new proposal for an action
    // that must be constructed in another module
    public fun create_proposal(
        multisig: &mut Multisig, 
        key: String, 
        execution_time: u64, // timestamp in ms
        expiration_epoch: u64,
        description: String,
        ctx: &mut TxContext
    ): &mut Proposal {
        assert_is_member(multisig, ctx);

        let mut proposal = Proposal { 
            id: object::new(ctx),
            description,
            execution_time,
            expiration_epoch,
            approved: vec_set::empty(), 
        };

        multisig.proposals.insert(key, proposal);

        multisig.proposals.get_mut(&key)
    }

    public fun add_action<A: store>(
        proposal: &mut Proposal,
        action: A
    ) {
        df::add(&mut proposal.id, ActionKey {}, action);
    }

    public fun add_access<A: store>(
        proposal: &mut Proposal,
        access: A
    ) {
        df::add(&mut proposal.id, AccessKey {}, access);
    }

    // remove a proposal that hasn't been approved yet
    // prevents malicious members to delete proposals that are still open
    public fun delete_proposal(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let (_, proposal) = multisig.proposals.remove(&key);
        assert!(proposal.approved.size() == 0, EProposalNotEmpty);
        
        let Proposal { 
            id, 
            expiration_epoch: _, 
            execution_time: _, 
            description: _, 
            approved: _ 
        } = proposal;
        id.delete();
    }

    // the signer agrees with the proposal
    public fun approve_proposal(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = multisig.proposals.get_mut(&key);
        proposal.approved.insert(ctx.sender()); // throws if already approved
    }

    // the signer removes his agreement
    public fun remove_approval(
        multisig: &mut Multisig, 
        key: String, 
        ctx: &mut TxContext
    ) {
        assert_is_member(multisig, ctx);

        let proposal = multisig.proposals.get_mut(&key);
        proposal.approved.remove(&ctx.sender());
    }

    // return the action if the number of signers is >= threshold
    public fun execute_proposal(
        multisig: &mut Multisig, 
        key: String, 
        clock: &Clock,
        ctx: &mut TxContext
    ): Promise {
        assert_is_member(multisig, ctx);

        let (_, proposal) = multisig.proposals.remove(&key);
        let Proposal { 
            mut id, 
            expiration_epoch: _, 
            execution_time, 
            description: _, 
            approved, 
        } = proposal;
        assert!(approved.size() >= multisig.threshold, EThresholdNotReached);
        assert!(clock.timestamp_ms() >= execution_time, ECantBeExecutedYet);

        Promise { multisig_addr: multisig.addr(), proposal_uid: id }
    }

    public fun get_action<A: store>(promise: &mut Promise): Action<A> {
        let inner = df::remove(&mut promise.proposal_uid, ActionKey {});
        Action { inner }
    }

    public fun get_access<A: store>(promise: &mut Promise): A {
        df::remove(&mut promise.proposal_uid, AccessKey {})
    }

    public fun complete_proposal(promise: Promise) {
        let Promise { multisig_addr: _, proposal_uid } = promise;
        assert!(!df::exists_(&mut proposal_uid, ActionKey {}), 0);
        assert!(!df::exists_(&mut proposal_uid, AccessKey {}), 0);
        proposal_uid.delete();
    }

    // === View functions ===

    public fun get_multisig_addr(promise: &Promise): address {
        promise.multisig_addr
    }

    public fun name(multisig: &Multisig): String {
        multisig.name
    }

    public fun threshold(multisig: &Multisig): u64 {
        multisig.threshold
    }

    public fun members(multisig: &Multisig): vector<address> {
        multisig.members.into_keys()
    }

    public fun addr(multisig: &Multisig): address {
        multisig.id.uid_to_inner().id_to_address()
    }

    public fun num_of_proposals(multisig: &Multisig): u64 {
        multisig.proposals.size()
    }

    public fun proposal(multisig: &Multisig, key: &String): &Proposal {
        multisig.proposals.get(key)
    }

    public fun description(proposal: &Proposal): String {
        proposal.description
    }

    public fun expiration_epoch(proposal: &Proposal): u64 {
        proposal.expiration_epoch
    }

    public fun execution_time(proposal: &Proposal): u64 {
        proposal.execution_time
    }

    public fun approved(proposal: &Proposal): vector<address> {
        proposal.approved.into_keys()
    }

    // === Package functions ===

    // called to access and execute the action
    public(package) fun action_mut<T: store>(action: &mut Action<T>): &mut T {
        &mut action.inner
    }

    // should be called after the action has been executed 
    public(package) fun unpack_action<T: store>(action: Action<T>): T {
        let Action { inner } = action;
        inner
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun set_name(multisig: &mut Multisig, name: String) {
        multisig.name = name;
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun set_threshold(multisig: &mut Multisig, threshold: u64) {
        multisig.threshold = threshold;
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun add_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = addresses.pop_back();
            multisig.members.insert(addr);
        }
    }

    // callable only in management.move, if the proposal has been accepted
    public(package) fun remove_members(multisig: &mut Multisig, mut addresses: vector<address>) {
        while (addresses.length() > 0) {
            let addr = addresses.pop_back();
            multisig.members.remove(&addr);
        }
    }

    public(package) fun uid_mut(multisig: &mut Multisig): &mut UID {
        &mut multisig.id
    }

    public(package) fun assert_is_member(multisig: &Multisig, ctx: &TxContext) {
        assert!(multisig.members.contains(&ctx.sender()), ECallerIsNotMember);
    }

    // === Test functions ===

    #[test_only]
    public fun assert_multisig_data_numbers(
        multisig: &Multisig,
        threshold: u64,
        members: u64,
        proposals: u64
    ) {
        assert!(multisig.threshold == threshold, 100);
        assert!(multisig.members.size() == members, 100);
        assert!(multisig.proposals.size() == proposals, 100);
    }
}

