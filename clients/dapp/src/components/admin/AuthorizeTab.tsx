import { useState, type Dispatch, type SetStateAction } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi } from "../../lib/abi";
import { buildPreview, type AdminAction, type PreviewContext } from "../../lib/preview";
import { markRegistered } from "../../lib/useVaultRegistration";
import { TxPreview } from "../TxPreview";
import { PolicyFields } from "./PolicyFields";

interface AuthorizeTabProps {
  gatewayAddress: Address;
  ctx: PreviewContext;
  agent: string;
  setAgent: Dispatch<SetStateAction<string>>;
  shareReceiver: string;
  setShareReceiver: Dispatch<SetStateAction<string>>;
}

export function AuthorizeTab(props: AuthorizeTabProps) {
  const { address, isConnected } = useAccount();
  const { writeContract, isPending } = useWriteContract();

  const [validUntil, setValidUntil] = useState(() =>
    // eslint-disable-next-line no-restricted-syntax -- lazy init, runs once at mount.
    Math.floor(Date.now() / 1000 + 86400).toString(),
  );
  const [maxPerPayment, setMaxPerPayment] = useState("100000000");
  const [maxPerWindow, setMaxPerWindow] = useState("1000000000");

  const validAgent = isAddress(props.agent);
  const validReceiver = isAddress(props.shareReceiver);

  const action: AdminAction | null =
    validAgent && validReceiver
      ? {
          kind: "authorizeAgent",
          agent: props.agent as Address,
          policy: {
            active: true,
            validUntil: BigInt(validUntil),
            maxPerPayment: BigInt(maxPerPayment),
            maxPerWindow: BigInt(maxPerWindow),
            shareReceiver: props.shareReceiver as Address,
          },
        }
      : null;

  const preview = action ? buildPreview(action, props.ctx) : null;

  const onSubmit = () => {
    if (!action || !preview?.ok) return;
    writeContract({
      address: props.gatewayAddress,
      abi: gatewayAbi,
      functionName: "authorizeAgent",
      args: [action.agent, action.policy],
    });
    if (address) markRegistered(address);
  };

  return (
    <section data-testid="authorize-form">
      <h2>Authorize agent</h2>
      <label>
        Agent address
        <input
          data-testid="agent-input"
          value={props.agent}
          onChange={(e) => props.setAgent(e.target.value)}
          placeholder="0x..."
        />
      </label>
      <PolicyFields
        validUntil={validUntil}
        setValidUntil={setValidUntil}
        maxPerPayment={maxPerPayment}
        setMaxPerPayment={setMaxPerPayment}
        maxPerWindow={maxPerWindow}
        setMaxPerWindow={setMaxPerWindow}
        shareReceiver={props.shareReceiver}
        setShareReceiver={props.setShareReceiver}
      />
      {preview && <TxPreview preview={preview} />}
      <button
        type="button"
        data-testid="authorize-submit"
        disabled={!isConnected || !preview?.ok || isPending}
        onClick={onSubmit}
      >
        Sign authorizeAgent with wallet
      </button>
    </section>
  );
}
