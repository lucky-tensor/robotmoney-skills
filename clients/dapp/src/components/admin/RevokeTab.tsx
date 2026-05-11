import { useAccount, useWriteContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi } from "../../lib/abi";
import { buildPreview, type AdminAction, type PreviewContext } from "../../lib/preview";
import { TxPreview } from "../TxPreview";

interface RevokeTabProps {
  gatewayAddress: Address;
  ctx: PreviewContext;
  agent: string;
}

export function RevokeTab(props: RevokeTabProps) {
  const { isConnected } = useAccount();
  const { writeContract, isPending } = useWriteContract();

  const action: AdminAction | null = isAddress(props.agent)
    ? { kind: "revokeAgent", agent: props.agent as Address }
    : null;
  const preview = action ? buildPreview(action, props.ctx) : null;

  const onSubmit = () => {
    if (!action || !preview?.ok) return;
    writeContract({
      address: props.gatewayAddress,
      abi: gatewayAbi,
      functionName: "revokeAgent",
      args: [action.agent],
    });
  };

  return (
    <section data-testid="revoke-form">
      <h2>Revoke agent</h2>
      {preview && <TxPreview preview={preview} />}
      <button
        type="button"
        data-testid="revoke-submit"
        disabled={!isConnected || !preview?.ok || isPending}
        onClick={onSubmit}
      >
        Sign revokeAgent with wallet
      </button>
    </section>
  );
}
