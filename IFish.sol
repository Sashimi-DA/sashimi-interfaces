pragma solidity ^0.8.16;

import "@openzeppelin/contracts/utils/structs/EnumerableSet.sol";
using EnumerableSet for EnumerableSet.AddressSet;

/////////////////////////////////////////////////////////
// IFish.sol
//
// Fast Integrated Storage House (FISH), is the built-in actor on
// a Sashimi subnet that is responsible for efficient on-chain
// storage built by storage records.
//
// The actor is called "FISH" because a full fish is what you
// get when you combine enough sashimi slices. Clever, I know.
//
// This actor maintains the following state tree structures:
//
// [] Index of CID -> Record:    Ability to search O(1) for data records
//								 based on their computed CID.							
// [] Record ID -> [CIDs]: 		 Depending on how the record is configured,
//								 a record could have multiple versions of its history
//							     stored in the state tree. Rent would be paid
//								 for each byte of each version.
//
// FISH is also responsible for the life-cycle of the data records.
// This includes:
//
// 1) Record Creation. A record is created by a user who provides configuration
//	  for the record, its historical storage, who owns the record, and which
//	  accounts have access to write to the record.
// 2) Record Reading. In full or in part (JSON-XPATH), FISH enables the system,
//	  RPC endpoints, or FEVM execution access to read data for retrieval or
//	  execution.
// 3) Rent Payments. FISH will utilize network gas and bandwidth on some interval
//	  to collect rent payments for records.
// 4) Record Updates. FISH will also enable the mutation of specific records. While the
//	  resulting content itself will get its own addressible CID, the latest CID pointer
//    for that given record ID will be established once it has changed.
// 5) Expiration and pruning. FISH will also utilize network gas to destroy or prune
//    records from storage and indexes when rent has been exhausted.
//
// This file demonstrates the interface that a solidity smart contract would interact with
// as part of a core precompilation library that is supplied to all Sashimi developers.
// Most of these methods should also be directly exposed via RPC endpoints to avoid
// expensive operations like MLOADing 256kb into EVM memory for insertion. That is to say,
// this interface is demonstrative of a combined smart contract and RPC experience for
// developers.
/////////////////////////////////////////////////////////
interface IFish {
	/////////////////////////////////////////////////////
	// Data Structures
	/////////////////////////////////////////////////////
	// A slice is the structure that defines a sashimi
	// data record.
	struct Slice {
		// A UUID for this record. Likely a combination of
		// the messeage sender, their nonce, the timestamp,
		// and a hash of the original configuration values.
		// This is immutable and will always refer to this record.
		bytes32 sliceId;

		// A set of addresses that are considered owners.
		// Owners can manage the slice account balance,
		// and add or remove approved record writers. 
		EnumerableSet.AddressSet owners;

		// Each slice has an associated FIL/ETH balance,
		// that is used to pay storage rent. When the balance
		// reaches zero, the record is immediately eligible
		// for state tree pruning.
		uint256 balance;

		// A set of addresses that are considered
		// valid writers. Only message senders that are
		// in this list can mutate the contents of the record.
		EnumerableSet.AddressSet writers;

		// A historical list of CIDs that are keys into the
		// actual content. The slice itself does not store
		// the raw bytes, but does store references to the
		// associated CIDs.
		bytes[] cids;

		// a configuration value that determines the amount
		// of history to maintain. the default is "0", which
		// means only the latest copy will be stored and
		// referenceable. the more history is stored, the more
		// storage rent will be required per epoch.
		uint256 historyDepth;
	}

	/////////////////////////////////////////////////////
	// Record Management
	//
	// These methods manage the concrete life-cycle and
	// configuration of individual slices. Outside of
	// #createSlice, all other methods will require
	// the message sender exists within the [owners] list.
	/////////////////////////////////////////////////////
	
	/////////////////////////////////////////////////////
	// createSlice 
	//
	// A user will call this method when they want to create a brand new
	// record. The record will come specified, along with the original
	// data. This method is considered "payable." Any funds sent
	// in with this call will result in the balance being deposited
	// into the resulting record's rent account.
	//
	// @param owners		a list of addresses to be considered owners of this record
	// @param writers		a list of addresses to be considered writers of this record
	// @param historyDepth	the number of historical records to keep around after each write
	// @param payload		the raw bytes for the initial contents of the record. could be empty.
	//
	// @return sliceID 		the resulting slice UUID
	// @return expiration 	the projected timestamp when the record will expire
	/////////////////////////////////////////////////////
	function createSlice(address[] calldata owners, address[] calldata writers, uint256 historyDepth, bytes payload) 
		payable external returns (bytes32 sliceID, uint256 expiration); 
	
	/////////////////////////////////////////////////////
	// fundSlice
	//
	// Anyone can provide additional funds to pay storage rent for
	// a given record.
	//
	// If a record does not exist, this method will revert.
	//
	// @param sliceId the UUID of the slice record you want to fund.
	/////////////////////////////////////////////////////
	function fundSlice(bytes32 sliceId) external payable;
	
	/////////////////////////////////////////////////////
	// addOwners
	//
	// This method is called by record owners to add a list
	// of addresses to the existing record owners list. Duplicates
	// will be ignored and the operation will be considered
	// a union of the existing and new sets.
	//
	// This method should violently revert the entire operation
	// if the UUID is missing or out of storage rent but not yet pruned. 
	//
	// After the method has returned, the new owners will have
	// root level permissions over the configuration of the record.
	//
	// @param sliceId   the UUID of the record the caller wants to mutate
	// @param newOwners the list of new owners to add to the record
	/////////////////////////////////////////////////////
	function addOwners(bytes32 sliceId, address[] calldata newOwners) external;
	
	/////////////////////////////////////////////////////
	// removeOwners
	//
	// This method is called by record owners to remove a list
	// of addresses from the existing record owners list.
	// Addresses that are requested to be removed but do not exist
	// will be silently ignored.
	//
	// This method should violently revert the entire operation
	// if the UUID is missing or out of storage rent but not yet pruned.
	//
	// This method will not prevent a user from revoking the entire
	// owner list. In this way, records can become immutable
	// and irrevocable much like a data trust.
	//
	// After the method has returned, it is guaranteed that the
	// provided addresses have had their ownership status revoked.
	//
	// @param sliceId   the UUID of the record the caller wants to mutate
	// @param newOwners the list of new owners to remove from the record
	/////////////////////////////////////////////////////
	function removeOwners(bytes32 sliceId, address[] calldata removeOwners) external;

	/////////////////////////////////////////////////////
	// addWriters
	//
	// This method is called by record owners to add a list
	// of approved writers to the given record. If duplicates
	// exist they will be silently ignored. After the call
	// returns, the provided addresses will have immediate write
	// access to the record.
	//
	// @param sliceId    the UUID of the record the caller wants to mutate
	// @param newWriters the list of new writers to add to the record
	/////////////////////////////////////////////////////
	function addWriters(bytes32 sliceId, address[] calldata newWriters) external;

	/////////////////////////////////////////////////////
	// removeWriters 
	//
	// This method is called by record owners to remove
	// a list of writers from a given record. If provided
	// addresses do not have writer access they will be
	// safely ignored. After the call returns the provided
	// addresses will be ensured to not have write access
	// to the record.
	//
	// @param sliceId       the UUID of the record the caller wants to mutate
	// @param removeWriters the list of writers to remove from the record
	/////////////////////////////////////////////////////
	function removeWriters(bytes32 sliceId, address[] calldata removeWriters) external;

	/////////////////////////////////////////////////////
	// setHistoryDepth
	//
	// The record owner will call this to set the history depth
	// for the record. Each write will create a new version of
	// the record in its history, storing up to *depth* copies.
	// Storage rent is costed per byte, so each historical version
	// will cost incrementally more rent from the record's
	// storage account.
	//
	// The default value for history depth is zero, meaning only
	// the most current copy is kept, and after each write the
	// previous version is completely pruned from the state tree.
	//
	// @param sliceId  the UUID of the record the caller wants to mutate
	// @param newDepth the number of historical versions of this record to keep
	/////////////////////////////////////////////////////
	function setHistoryDepth(bytes32 sliceId, uint256 newDepth) external;

	/////////////////////////////////////////////////////
	// Record Introspection
	//
	// Reading slices, or parsing subsections of them is
	// a permissionless activity and so anyone can call these.
	// These methods are by default considered also
	// exposed directly as eth_* RPC endpoints.
	/////////////////////////////////////////////////////
	
	/////////////////////////////////////////////////////
	// getSlice
	//
	// Given a UUID for a slice, return the slice structure
	// describing the record configuration and rent balance.
	//
	// @param sliceID the UUID for the slice you want to introspect.
	// @return slice a full serialized Slice structure
	/////////////////////////////////////////////////////
	function getSlice(bytes32 sliceId) external returns (Slice memory slice);

	/////////////////////////////////////////////////////
	// getLatestSliceData
	//
	// This method returns the entire payload for the latest
	// version of the record.
	//
	// @param sliceId the UUID of the record you want the latest contents for
	// @return payload the raw bytes payload of the record contents
	/////////////////////////////////////////////////////
	function getLatestSliceData(bytes32 sliceId) external returns (bytes memory payload);

	/////////////////////////////////////////////////////
	// getCID
	//
	// Given a CID, return the payload for it. If the CID
	// is no longer rented it is treated as an invariant,
	// and will fail the transaction or RPC call.
	//
	// @param cid      the CID you want the data for
	// @return payload the raw payload for that content
	/////////////////////////////////////////////////////
	function getCID(bytes calldata cid) external returns (bytes memory payload);

	/////////////////////////////////////////////////////
	// parseLatestSlice
	//
	// This method returns a sub-portion of the data, serialized
	// directly into an in-memory EVM primative. The record
	// contents are interpreted as raw JSON, and the provided
	// xpath descriptor is used for interpreted selection.
	//
	// Path descriptors can traverse children, introspect into arrays,
	// and key into hashes, and return primatives as well as lists.
	//		- 'hero.weight' => uint256
	//		- 'hero.items'  => [bytes32, bytes32, bytes32]
	//		- 'hero.weapons[1].type => 'axe'
	//		- 'party.members['scott'].height => uint256
	//
	// @param sliceId the UUID of the record you want to read
	// @param xpath	  the path descriptor for the element
	// @return the serialized data for that path descriptor.
	/////////////////////////////////////////////////////
	function parseLatestSliceUInt(bytes32 sliceId, string xpath) external returns (uint256);	
	function parseLatestSliceUintArray(bytes32 slideId, string xpath) external returns (uint256[] memory);	
	function parseLatestSliceString(bytes32 sliceId, string xpath) external returns (string);	
	function parseLatestSliceStringArray(bytes32 slideId, string xpath) external returns (string[] memory);	
	function parseLatestSliceBytes32(bytes32 sliceId, string xpath) external returns (bytes32);	
	function parseLatestSliceBytes32Array(bytes32 sliceId, string xpath) external returns (bytes32[] memory);	
	function parseLatestSliceAddress(bytes32 sliceId, string xpath) external returns (address);	
	function parseLatestSliceAddressArray(bytes32 slideId, string xpath) external returns (address[] memory);	
	function parseLatestSliceBytes(bytes32 slideId, string xpath) external returns (bytes);	
	function parseLatestSliceBytesArray(bytes32 sliceId, string xpath) external returns (bytes[] memory);	
	
	/////////////////////////////////////////////////////
	// parseCID
	//
	// These methods are essentially the same as #parseLatestSlice,
	// but provides a CID-specifc interface. These methods
	// will fail if the CID is invalid or out of rent.
	/////////////////////////////////////////////////////
	function parseCIDUInt(bytes cid, string xpath) external returns (uint256);	
	function parseCIDUintArray(bytes cid, string xpath) external returns (uint256[] memory);	
	function parseCIDString(bytes cid, string xpath) external returns (string);	
	function parseCIDStringArray(bytes cid, string xpath) external returns (string[] memory);	
	function parseCIDBytes32(bytes cid, string xpath) external returns (bytes32);	
	function parseCIDBytes32Array(bytes cid, string xpath) external returns (bytes32[] memory);	
	function parseCIDAddress(bytes cid, string xpath) external returns (address);	
	function parseCIDAddressArray(bytes cid, string xpath) external returns (address[] memory);	
	function parseCIDBytes(bytes cid, string xpath) external returns (bytes);	
	function parseCIDBytesArray(bytes cid, string xpath) external returns (bytes[] memory);	

	/////////////////////////////////////////////////////
	// Record Writing
	//
	// This collection of interfaces is used to write
	// full or partial records. Each method must be called
	// by an address that has writer access, lest the
	// entire transaction revert.
	//
	/////////////////////////////////////////////////////
	
	/////////////////////////////////////////////////////
	// writeSlice
	//
	// This method can only be called by valid writers on
	// active slices with non-zero rent. The caller
	// will create an entirely new CID, and potentially
	// a historical version record as well depending on
	// configuration. This method will replace an
	// entire record's contents with the provided bytes.
	//
	// @param sliceId the UUID of the record the caller wishes to mutate
	// @param payload the raw bytes for the new record contents
	/////////////////////////////////////////////////////
	function writeSlice(bytes32 sliceId, bytes calldata payload) external;
	
	/////////////////////////////////////////////////////
	// writeSubSlice
	//
	// Similar to parse, these methods will take a slice ID,
	// an xpath, and some inputs to prepare a new record version.
	// The record version will include the newly updated
	// paths, and will not type-check the new input against
	// its replaced values.
	//
	// To avoid CID churn on updating multiple paths, callers
	// must pass in a commit flag. Subsequent calls without
	// a commit flag will queue up state for a single commit
	// across multiple sub slice writes. Uncommitted subslices
	// will result in paid gas but loss of data.
	//
	// @param sliceId the UUID of the record the caller wishes to mutate
	// @param xpath	  the path to update
	// @param payload the element's value at that path.
	// @param commit  must be called at least once per transaction by a valid writer
	/////////////////////////////////////////////////////
	function writeSubSliceUInt(bytes32 sliceId, string xpath, uint256 payload, bool commit) external;
	function writeSubSliceUIntArray(bytes32 sliceId, string xpath, uint256[] memory payload, bool commit) external;
	function writeSubSliceString(bytes32 sliceId, string xpath, string payload, bool commit) external;
	function writeSubSliceStringArray(bytes32 sliceId, string xpath, string[] memory payload, bool commit) external;
	function writeSubSliceBytes32(bytes32 sliceId, string xpath, bytes32 payload, bool commit) external;
	function writeSubSliceBytes32Array(bytes32 sliceId, string xpath, bytes32[] memory payload, bool commit) external;
	function writeSubSliceAddress(bytes32 sliceId, string xpath, address payload, bool commit) external;
	function writeSubSliceAddressArray(bytes32 sliceId, string xpath, address[] memory payload, bool commit) external;
	function writeSubSliceBytes(bytes32 sliceId, string xpath, bytes payload, bool commit) external;
	function writeSubSliceBytesArray(bytes32 sliceId, string xpath, bytes[] memory payload, bool commit) external;
}
