import { useState, type ReactNode } from "react";

export interface TabDef {
  id: string;
  label: string;
  content: ReactNode;
  hidden?: boolean;
}

interface TabsProps {
  tabs: TabDef[];
  defaultTabId?: string;
}

export function Tabs({ tabs, defaultTabId }: TabsProps) {
  const visible = tabs.filter((t) => !t.hidden);
  const initial = visible.find((t) => t.id === defaultTabId)?.id ?? visible[0]?.id ?? "";
  const [active, setActive] = useState(initial);
  const current = visible.find((t) => t.id === active) ?? visible[0];

  return (
    <div className="tabs" data-testid="admin-tabs">
      <div role="tablist" className="tabs-list">
        {visible.map((t) => {
          const selected = t.id === current?.id;
          return (
            <button
              key={t.id}
              role="tab"
              type="button"
              aria-selected={selected}
              data-testid={`tab-${t.id}`}
              data-active={selected}
              className="tab-trigger"
              onClick={() => setActive(t.id)}
            >
              {t.label}
            </button>
          );
        })}
      </div>
      {current && (
        <div role="tabpanel" className="tab-panel" data-testid={`tabpanel-${current.id}`}>
          {current.content}
        </div>
      )}
    </div>
  );
}
