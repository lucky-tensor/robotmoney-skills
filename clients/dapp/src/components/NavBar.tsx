interface NavBarProps {
  path: string;
  onNavigate: (path: string) => void;
}

const LINKS = [
  { path: "/", label: "Dashboard" },
  { path: "/admin", label: "Admin" },
];

export function NavBar({ path, onNavigate }: NavBarProps) {
  return (
    <header className="nav" data-testid="nav">
      <a
        className="nav-brand"
        href="/"
        onClick={(e) => {
          e.preventDefault();
          onNavigate("/");
        }}
      >
        ROBOT<span>MONEY</span>
      </a>
      <nav className="nav-links">
        {LINKS.map((l) => (
          <a
            key={l.path}
            href={l.path}
            data-testid={`nav-${l.label.toLowerCase()}`}
            data-active={path === l.path}
            onClick={(e) => {
              e.preventDefault();
              onNavigate(l.path);
            }}
          >
            {l.label}
          </a>
        ))}
      </nav>
    </header>
  );
}
