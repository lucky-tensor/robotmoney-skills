/**
 * useRotationState — owns the agent-rotation flow state machine.
 *
 * Encapsulates the rotation form fields, derives the two-step revoke +
 * authorize previews via `buildPreview`, validates the combined transition
 * via `composeRotationPreview`, and exposes the wagmi writeContract
 * handlers for each step. RotationTab is left as render-only.
 */
import { useState } from "react";
import { useWriteContract } from "wagmi";
import { isAddress, type Address } from "viem";
import { gatewayAbi } from "./abi";
import { buildPreview, type AdminAction, type Preview, type PreviewContext } from "./preview";
import { composeRotationPreview } from "./rotation";

export type RotationStep = "idle" | "revoke-sent" | "done";

export interface RotationStateHandle {
  // form state
  oldAgent: string;
  setOldAgent: (v: string) => void;
  newAgent: string;
  setNewAgent: (v: string) => void;
  validUntil: string;
  setValidUntil: React.Dispatch<React.SetStateAction<string>>;
  maxPerPayment: string;
  setMaxPerPayment: React.Dispatch<React.SetStateAction<string>>;
  maxPerWindow: string;
  setMaxPerWindow: React.Dispatch<React.SetStateAction<string>>;
  shareReceiver: string;
  setShareReceiver: React.Dispatch<React.SetStateAction<string>>;

  // derived
  step: RotationStep;
  revokePreview: Preview | null;
  authorizePreview: Preview | null;
  combinedRiskAnnotation: string | null;
  combinedError: string | null;
  previewsOk: boolean;
  isPending: boolean;

  // handlers
  onRevoke: () => void;
  onAuthorize: () => void;
}

export function useRotationState(
  gatewayAddress: Address,
  ctx: PreviewContext,
): RotationStateHandle {
  const { writeContract, isPending } = useWriteContract();

  const [oldAgentRaw, setOldAgentRaw] = useState("");
  const [newAgentRaw, setNewAgentRaw] = useState("");
  const [validUntil, setValidUntil] = useState(() =>
    // eslint-disable-next-line no-restricted-syntax -- lazy init, runs once at mount.
    Math.floor(Date.now() / 1000 + 86400).toString(),
  );
  const [maxPerPayment, setMaxPerPayment] = useState("100000000");
  const [maxPerWindow, setMaxPerWindow] = useState("1000000000");
  const [shareReceiver, setShareReceiver] = useState("");
  const [step, setStep] = useState<RotationStep>("idle");

  const setOldAgent = (v: string) => {
    setOldAgentRaw(v);
    setStep("idle");
  };
  const setNewAgent = (v: string) => {
    setNewAgentRaw(v);
    setStep("idle");
  };

  const validOld = isAddress(oldAgentRaw);
  const validNew = isAddress(newAgentRaw);
  const validReceiver = isAddress(shareReceiver);

  let combinedRiskAnnotation: string | null = null;
  let combinedError: string | null = null;
  let combinedOk = false;
  if (validOld && validNew && validReceiver) {
    try {
      const r = composeRotationPreview(oldAgentRaw, newAgentRaw, {
        shareReceiver,
        validUntil: Number(validUntil),
        maxPerDeposit: BigInt(maxPerPayment),
        maxPerWindow: BigInt(maxPerWindow),
      });
      combinedRiskAnnotation = r.combinedRiskAnnotation;
      combinedOk = true;
    } catch (err) {
      combinedError = (err as Error).message;
    }
  }

  const revokeAction: AdminAction | null = validOld
    ? { kind: "revokeAgent", agent: oldAgentRaw as Address }
    : null;
  const authorizeAction: AdminAction | null =
    validNew && validReceiver
      ? {
          kind: "authorizeAgent",
          agent: newAgentRaw as Address,
          policy: {
            active: true,
            validUntil: BigInt(validUntil),
            maxPerPayment: BigInt(maxPerPayment),
            maxPerWindow: BigInt(maxPerWindow),
            shareReceiver: shareReceiver as Address,
          },
        }
      : null;

  const revokePreview = revokeAction ? buildPreview(revokeAction, ctx) : null;
  const authorizePreview = authorizeAction ? buildPreview(authorizeAction, ctx) : null;
  const previewsOk = combinedOk && revokePreview?.ok === true && authorizePreview?.ok === true;

  const onRevoke = () => {
    if (!revokeAction || revokePreview?.ok !== true) return;
    writeContract({
      address: gatewayAddress,
      abi: gatewayAbi,
      functionName: "revokeAgent",
      args: [revokeAction.agent],
    });
    setStep("revoke-sent");
  };

  const onAuthorize = () => {
    if (!authorizeAction || authorizePreview?.ok !== true) return;
    writeContract({
      address: gatewayAddress,
      abi: gatewayAbi,
      functionName: "authorizeAgent",
      args: [authorizeAction.agent, authorizeAction.policy],
    });
    setStep("done");
  };

  return {
    oldAgent: oldAgentRaw,
    setOldAgent,
    newAgent: newAgentRaw,
    setNewAgent,
    validUntil,
    setValidUntil,
    maxPerPayment,
    setMaxPerPayment,
    maxPerWindow,
    setMaxPerWindow,
    shareReceiver,
    setShareReceiver,
    step,
    revokePreview,
    authorizePreview,
    combinedRiskAnnotation,
    combinedError,
    previewsOk,
    isPending,
    onRevoke,
    onAuthorize,
  };
}
