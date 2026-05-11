import { useState } from "react";
import { useAccount, useWriteContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi } from "../../lib/abi";
import { buildPreview, type AdminAction, type PreviewContext } from "../../lib/preview";
import { composeRotationPreview } from "../../lib/rotation";
import { TxPreview } from "../TxPreview";
import { PolicyFields } from "./PolicyFields";

interface RotationTabProps {
  gatewayAddress: Address;
  ctx: PreviewContext;
}

export function RotationTab(props: RotationTabProps) {
  const { isConnected } = useAccount();
  const { writeContract, isPending } = useWriteContract();

  const [oldAgent, setOldAgent] = useState("");
  const [newAgent, setNewAgent] = useState("");
  const [validUntil, setValidUntil] = useState(() =>
    // eslint-disable-next-line no-restricted-syntax -- lazy init, runs once at mount.
    Math.floor(Date.now() / 1000 + 86400).toString(),
  );
  const [maxPerPayment, setMaxPerPayment] = useState("100000000");
  const [maxPerWindow, setMaxPerWindow] = useState("1000000000");
  const [shareReceiver, setShareReceiver] = useState("");
  const [step, setStep] = useState<"idle" | "revoke-sent" | "done">("idle");

  const validOld = isAddress(oldAgent);
  const validNew = isAddress(newAgent);
  const validReceiver = isAddress(shareReceiver);

  let rotationPreview: ReturnType<typeof composeRotationPreview> | null = null;
  let rotationPreviewError: string | null = null;
  if (validOld && validNew && validReceiver) {
    try {
      rotationPreview = composeRotationPreview(oldAgent, newAgent, {
        shareReceiver,
        validUntil: Number(validUntil),
        maxPerDeposit: BigInt(maxPerPayment),
        maxPerWindow: BigInt(maxPerWindow),
      });
    } catch (err) {
      rotationPreviewError = (err as Error).message;
    }
  }

  const revokeAction: AdminAction | null = validOld
    ? { kind: "revokeAgent", agent: oldAgent as Address }
    : null;
  const authorizeAction: AdminAction | null =
    validNew && validReceiver
      ? {
          kind: "authorizeAgent",
          agent: newAgent as Address,
          policy: {
            active: true,
            validUntil: BigInt(validUntil),
            maxPerPayment: BigInt(maxPerPayment),
            maxPerWindow: BigInt(maxPerWindow),
            shareReceiver: shareReceiver as Address,
          },
        }
      : null;

  const revokePrev = revokeAction ? buildPreview(revokeAction, props.ctx) : null;
  const authorizePrev = authorizeAction ? buildPreview(authorizeAction, props.ctx) : null;

  const previewsOk =
    rotationPreview !== null && revokePrev?.ok === true && authorizePrev?.ok === true;

  const onRevoke = () => {
    if (!revokeAction || !revokePrev?.ok) return;
    writeContract({
      address: props.gatewayAddress,
      abi: gatewayAbi,
      functionName: "revokeAgent",
      args: [revokeAction.agent],
    });
    setStep("revoke-sent");
  };

  const onAuthorize = () => {
    if (!authorizeAction || !authorizePrev?.ok) return;
    writeContract({
      address: props.gatewayAddress,
      abi: gatewayAbi,
      functionName: "authorizeAgent",
      args: [authorizeAction.agent, authorizeAction.policy],
    });
    setStep("done");
  };

  return (
    <section data-testid="rotation-form">
      <h2>Agent rotation (revoke old → authorize new)</h2>
      <p>
        Both previews must be confirmed before wallet signing begins. Do not close this dialog
        between transactions.
      </p>

      {rotationPreview && (
        <p data-testid="rotation-combined-risk" className="rotation-risk-banner">
          {rotationPreview.combinedRiskAnnotation}
        </p>
      )}
      {rotationPreviewError && (
        <p data-testid="rotation-preview-error" className="error">
          {rotationPreviewError}
        </p>
      )}

      <label>
        Old agent address (to revoke)
        <input
          data-testid="rotation-old-agent-input"
          value={oldAgent}
          onChange={(e) => {
            setOldAgent(e.target.value);
            setStep("idle");
          }}
          placeholder="0x..."
        />
      </label>
      <label>
        New agent address (to authorize)
        <input
          data-testid="rotation-new-agent-input"
          value={newAgent}
          onChange={(e) => {
            setNewAgent(e.target.value);
            setStep("idle");
          }}
          placeholder="0x..."
        />
      </label>
      <PolicyFields
        testIdPrefix="rotation-"
        validUntil={validUntil}
        setValidUntil={setValidUntil}
        maxPerPayment={maxPerPayment}
        setMaxPerPayment={setMaxPerPayment}
        maxPerWindow={maxPerWindow}
        setMaxPerWindow={setMaxPerWindow}
        shareReceiver={shareReceiver}
        setShareReceiver={setShareReceiver}
      />

      <div data-testid="rotation-step1">
        <h3>Step 1: revoke old agent</h3>
        {revokePrev && <TxPreview preview={revokePrev} />}
        <button
          type="button"
          data-testid="rotation-revoke-submit"
          disabled={!isConnected || !previewsOk || step !== "idle" || isPending}
          onClick={onRevoke}
        >
          Step 1 — Sign revokeAgent(old) with wallet
        </button>
      </div>

      <div data-testid="rotation-step2">
        <h3>Step 2: authorize new agent</h3>
        {authorizePrev && <TxPreview preview={authorizePrev} />}
        <button
          type="button"
          data-testid="rotation-authorize-submit"
          disabled={!isConnected || !previewsOk || step !== "revoke-sent" || isPending}
          onClick={onAuthorize}
        >
          Step 2 — Sign authorizeAgent(new) with wallet
        </button>
      </div>

      {step === "done" && (
        <p data-testid="rotation-complete">Rotation complete. Verify on-chain state.</p>
      )}
    </section>
  );
}
