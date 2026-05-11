/**
 * VerificationBanner — gateway bytecode hash verification status.
 * Rendered at the app shell so the refusal banner is visible before
 * wallet connect / before the Agents panel mounts.
 */
import type { VerificationState } from "../lib/useGatewayVerifier";

interface Props {
  state: VerificationState;
}

export function VerificationBanner({ state }: Props) {
  if (state.status === "verified") return null;
  return (
    <div className="verification-banner-wrap">
      <section data-testid="gateway-verification-status">
        {state.status === "pending" && (
          <p data-testid="gateway-verification-pending">
            Verifying gateway bytecode hash… Admin writes are disabled until verification completes.
          </p>
        )}
        {state.status === "refused" && (
          <p data-testid="gateway-verification-refused" className="unsafe-banner">
            <strong>Gateway verification refused — admin writes disabled.</strong> {state.reason}
          </p>
        )}
      </section>
    </div>
  );
}
