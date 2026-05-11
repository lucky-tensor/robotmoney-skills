import { useAccount } from "wagmi";
import type { Address } from "viem";
import type { PreviewContext } from "../../lib/preview";
import { useRotationState } from "../../lib/useRotationState";
import { TxPreview } from "../TxPreview";
import { PolicyFields } from "./PolicyFields";

type Props = Readonly<{
  gatewayAddress: Address;
  ctx: PreviewContext;
}>;

export function RotationTab(props: Props) {
  const { isConnected } = useAccount();
  const r = useRotationState(props.gatewayAddress, props.ctx);

  const disableRevoke = !isConnected || !r.previewsOk || r.step !== "idle" || r.isPending;
  const disableAuthorize = !isConnected || !r.previewsOk || r.step !== "revoke-sent" || r.isPending;

  return (
    <section data-testid="rotation-form">
      <h2>Agent rotation (revoke old → authorize new)</h2>
      <p>
        Both previews must be confirmed before wallet signing begins. Do not close this dialog
        between transactions.
      </p>

      {r.combinedRiskAnnotation && (
        <p data-testid="rotation-combined-risk" className="rotation-risk-banner">
          {r.combinedRiskAnnotation}
        </p>
      )}
      {r.combinedError && (
        <p data-testid="rotation-preview-error" className="error">
          {r.combinedError}
        </p>
      )}

      <label>
        Old agent address (to revoke)
        <input
          data-testid="rotation-old-agent-input"
          value={r.oldAgent}
          onChange={(e) => r.setOldAgent(e.target.value)}
          placeholder="0x..."
        />
      </label>
      <label>
        New agent address (to authorize)
        <input
          data-testid="rotation-new-agent-input"
          value={r.newAgent}
          onChange={(e) => r.setNewAgent(e.target.value)}
          placeholder="0x..."
        />
      </label>
      <PolicyFields
        testIdPrefix="rotation-"
        validUntil={r.validUntil}
        setValidUntil={r.setValidUntil}
        maxPerPayment={r.maxPerPayment}
        setMaxPerPayment={r.setMaxPerPayment}
        maxPerWindow={r.maxPerWindow}
        setMaxPerWindow={r.setMaxPerWindow}
        shareReceiver={r.shareReceiver}
        setShareReceiver={r.setShareReceiver}
      />

      <div data-testid="rotation-step1">
        <h3>Step 1: revoke old agent</h3>
        {r.revokePreview && <TxPreview preview={r.revokePreview} />}
        <button
          type="button"
          data-testid="rotation-revoke-submit"
          disabled={disableRevoke}
          onClick={r.onRevoke}
        >
          Step 1 — Sign revokeAgent(old) with wallet
        </button>
      </div>

      <div data-testid="rotation-step2">
        <h3>Step 2: authorize new agent</h3>
        {r.authorizePreview && <TxPreview preview={r.authorizePreview} />}
        <button
          type="button"
          data-testid="rotation-authorize-submit"
          disabled={disableAuthorize}
          onClick={r.onAuthorize}
        >
          Step 2 — Sign authorizeAgent(new) with wallet
        </button>
      </div>

      {r.step === "done" && (
        <p data-testid="rotation-complete">Rotation complete. Verify on-chain state.</p>
      )}
    </section>
  );
}
