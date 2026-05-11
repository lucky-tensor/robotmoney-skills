import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi, ROLE_HASH, type RoleName } from "../../lib/abi";
import { buildPreview, type AdminAction, type PreviewContext } from "../../lib/preview";
import { TxPreview } from "../TxPreview";

type Props = Readonly<{
  role: RoleName;
  gatewayAddress: Address;
  ctx: PreviewContext;
  /** Inline note shown under the heading. */
  description: React.ReactNode;
}>;

const SLUG: Record<RoleName, string> = {
  ADMIN_ROLE: "admin",
  PAUSER_ROLE: "pauser",
};

export function RoleTab(props: Props) {
  const { isConnected } = useAccount();
  const { writeContract, isPending } = useWriteContract();
  const [account, setAccount] = useState("");

  const slug = SLUG[props.role];
  const valid = isAddress(account);

  const grantAction: AdminAction | null = valid
    ? { kind: "grantRole", role: props.role, account: account as Address }
    : null;
  const revokeAction: AdminAction | null = valid
    ? { kind: "revokeRole", role: props.role, account: account as Address }
    : null;

  const grantPreview = grantAction ? buildPreview(grantAction, props.ctx) : null;
  const revokePreview = revokeAction ? buildPreview(revokeAction, props.ctx) : null;

  const submit = (fn: "grantRole" | "revokeRole", target: Address) => {
    writeContract({
      address: props.gatewayAddress,
      abi: gatewayAbi,
      functionName: fn,
      args: [ROLE_HASH[props.role], target],
    });
  };

  return (
    <section data-testid={`${slug}-role-form`}>
      <h2>{props.role} grant / revoke</h2>
      {props.description}
      <label>
        {props.role.replace("_ROLE", "")} account address
        <input
          data-testid={`${slug}-account-input`}
          value={account}
          onChange={(e) => setAccount(e.target.value)}
          placeholder="0x..."
        />
      </label>
      {grantPreview && (
        <div data-testid={`grant-${slug}-preview-wrap`}>
          <TxPreview preview={grantPreview} />
        </div>
      )}
      <button
        type="button"
        data-testid={`grant-${slug}-submit`}
        disabled={!isConnected || !grantPreview?.ok || isPending}
        onClick={() => grantAction && grantPreview?.ok && submit("grantRole", grantAction.account)}
      >
        Sign grantRole({props.role}) with wallet
      </button>
      {revokePreview && (
        <div data-testid={`revoke-${slug}-preview-wrap`}>
          <TxPreview preview={revokePreview} />
        </div>
      )}
      <button
        type="button"
        data-testid={`revoke-${slug}-submit`}
        disabled={!isConnected || !revokePreview?.ok || isPending}
        onClick={() =>
          revokeAction && revokePreview?.ok && submit("revokeRole", revokeAction.account)
        }
      >
        Sign revokeRole({props.role}) with wallet
      </button>
    </section>
  );
}
