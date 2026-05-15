/**
 * ProtocolStats — reads GET /v1/stats and renders the protocol stats bar.
 *
 * Shows aggregate TVL, depositor count, and the most recent activity events.
 * Works without a connected wallet.
 *
 * issue #318 — protocol layer.
 */
import { useEffect, useState } from "react";
import type { FetchLike, StatsResponse } from "../lib/explorerApi";
import { fetchStats } from "../lib/explorerApi";

interface ProtocolStatsProps {
  apiUrl: string;
  fetchImpl?: FetchLike;
}

type State =
  | { phase: "loading" }
  | { phase: "error"; message: string }
  | { phase: "ok"; stats: StatsResponse };

export function ProtocolStats({ apiUrl, fetchImpl }: ProtocolStatsProps) {
  const [state, setState] = useState<State>({ phase: "loading" });

  useEffect(() => {
    const ac = new AbortController();
    fetchStats(apiUrl, { fetchImpl, signal: ac.signal })
      .then((stats) => setState({ phase: "ok", stats }))
      .catch((err: unknown) => {
        if (ac.signal.aborted) return;
        setState({ phase: "error", message: String(err) });
      });
    return () => ac.abort();
  }, [apiUrl, fetchImpl]);

  if (state.phase === "loading") {
    return (
      <section data-testid="protocol-stats">
        <p data-testid="protocol-stats-loading">Loading stats…</p>
      </section>
    );
  }
  if (state.phase === "error") {
    return (
      <section data-testid="protocol-stats">
        <p data-testid="protocol-stats-error">{state.message}</p>
      </section>
    );
  }

  const { stats } = state;

  return (
    <section data-testid="protocol-stats" className="protocol-stats">
      <div className="stat-grid">
        <div className="stat-card">
          <p className="stat-label">Aggregate TVL</p>
          <p data-testid="protocol-stats-tvl" className="stat-value font-mono">
            {stats.aggregate_tvl}
          </p>
        </div>
        <div className="stat-card">
          <p className="stat-label">Depositors</p>
          <p data-testid="protocol-stats-depositors" className="stat-value">
            {stats.depositor_count}
          </p>
        </div>
      </div>

      {stats.recent_activity.length > 0 && (
        <div data-testid="protocol-stats-activity">
          <h3>Recent Activity</h3>
          <ul>
            {stats.recent_activity.map((event, i) => (
              // biome-ignore lint/suspicious/noArrayIndexKey: stable fixture list
              <li key={i} data-testid="protocol-stats-activity-item">
                <span data-testid="protocol-stats-activity-kind">{event.kind}</span>
                {" @ block "}
                <span data-testid="protocol-stats-activity-block">{event.block_number}</span>
              </li>
            ))}
          </ul>
        </div>
      )}

      <p data-testid="protocol-stats-freshness">Block {stats.block_number}</p>
    </section>
  );
}
