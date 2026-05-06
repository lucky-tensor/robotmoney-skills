// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import {Test} from "forge-std/Test.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {AccessRoles} from "../gateway/AccessRoles.sol";

/// @dev Concrete harness exposing AccessRoles internals for test purposes.
contract AccessRolesHarness is AccessRoles {
    constructor(address admin) {
        _grantRole(DEFAULT_ADMIN_ROLE, admin);
        _grantRole(ADMIN_ROLE, admin);
    }

    function exposed_assertRoleSeparation(address account) external view {
        _assertRoleSeparation(account);
    }
}

contract AccessRolesTest is Test {
    AccessRolesHarness internal roles;

    address internal admin = makeAddr("admin");
    address internal pauser = makeAddr("pauser");
    address internal agent = makeAddr("agent");
    address internal stranger = makeAddr("stranger");

    function setUp() public {
        roles = new AccessRolesHarness(admin);
    }

    // --- Role-constant identity ---------------------------------------------

    function test_adminRole_isKeccakOfName() public view {
        assertEq(roles.ADMIN_ROLE(), keccak256("ADMIN_ROLE"));
    }

    function test_pauserRole_isKeccakOfName() public view {
        assertEq(roles.PAUSER_ROLE(), keccak256("PAUSER_ROLE"));
    }

    function test_agentRole_isKeccakOfName() public view {
        assertEq(roles.AGENT_ROLE(), keccak256("AGENT_ROLE"));
    }

    // --- Role-distinctness invariant ----------------------------------------

    function test_allRoleIds_areDistinct() public view {
        bytes32 a = roles.ADMIN_ROLE();
        bytes32 p = roles.PAUSER_ROLE();
        bytes32 g = roles.AGENT_ROLE();
        bytes32 d = 0x00; // DEFAULT_ADMIN_ROLE

        assertTrue(a != p, "ADMIN == PAUSER");
        assertTrue(a != g, "ADMIN == AGENT");
        assertTrue(p != g, "PAUSER == AGENT");
        assertTrue(a != d, "ADMIN == DEFAULT_ADMIN");
        assertTrue(p != d, "PAUSER == DEFAULT_ADMIN");
        assertTrue(g != d, "AGENT == DEFAULT_ADMIN");
    }

    // --- Role-separation: AGENT must not also be ADMIN/PAUSER ---------------

    function test_grantAgent_revertsIfAlreadyAdmin() public {
        vm.prank(admin);
        vm.expectRevert(AccessRoles.RoleSeparationViolated.selector);
        roles.grantRole(roles.AGENT_ROLE(), admin);
    }

    function test_grantAgent_revertsIfAlreadyPauser() public {
        vm.prank(admin);
        roles.grantRole(roles.PAUSER_ROLE(), pauser);

        vm.prank(admin);
        vm.expectRevert(AccessRoles.RoleSeparationViolated.selector);
        roles.grantRole(roles.AGENT_ROLE(), pauser);
    }

    function test_grantAdmin_revertsIfAlreadyAgent() public {
        vm.prank(admin);
        roles.grantRole(roles.AGENT_ROLE(), agent);

        vm.prank(admin);
        vm.expectRevert(AccessRoles.RoleSeparationViolated.selector);
        roles.grantRole(roles.ADMIN_ROLE(), agent);
    }

    function test_grantPauser_revertsIfAlreadyAgent() public {
        vm.prank(admin);
        roles.grantRole(roles.AGENT_ROLE(), agent);

        vm.prank(admin);
        vm.expectRevert(AccessRoles.RoleSeparationViolated.selector);
        roles.grantRole(roles.PAUSER_ROLE(), agent);
    }

    function test_grantAgent_succeedsForFreshAccount() public {
        vm.prank(admin);
        roles.grantRole(roles.AGENT_ROLE(), agent);
        assertTrue(roles.hasRole(roles.AGENT_ROLE(), agent));
    }

    function test_adminAndPauser_canCoexistOnSameAccount() public {
        // Only AGENT is exclusive; ADMIN+PAUSER overlap is permitted.
        vm.prank(admin);
        roles.grantRole(roles.PAUSER_ROLE(), admin);
        assertTrue(roles.hasRole(roles.ADMIN_ROLE(), admin));
        assertTrue(roles.hasRole(roles.PAUSER_ROLE(), admin));
    }

    // --- assertRoleSeparation helper ----------------------------------------

    function test_assertRoleSeparation_passesForAdminOnly() public view {
        roles.exposed_assertRoleSeparation(admin);
    }

    function test_assertRoleSeparation_passesForFreshAccount() public view {
        roles.exposed_assertRoleSeparation(stranger);
    }

    function test_assertRoleSeparation_passesForAgentOnly() public {
        vm.prank(admin);
        roles.grantRole(roles.AGENT_ROLE(), agent);
        roles.exposed_assertRoleSeparation(agent);
    }

    function test_grantRole_unauthorizedCaller_reverts() public {
        // Sanity: non-admin cannot grant.
        vm.prank(stranger);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector,
                stranger,
                bytes32(0)
            )
        );
        roles.grantRole(roles.AGENT_ROLE(), agent);
    }
}
