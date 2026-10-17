LEGEND = ["● working", "○ ready", "◐ review / CI running", "✓ done / green", "✗ failing", "⏸ blocked", "! needs you (session gone or unknown)", "? unknown"]
KEYWORDS = "q quit · t tree · l ladder · r redraw"
def legend_lines(w, keys, wide, lead):
    rows, cur = [], ""
    for item in [l.replace("! needs you", "! needs you or the lead") if lead else l for l in LEGEND] + ([KEYWORDS] if keys and not wide else []):
        if cur and len(cur) + 3 + len(item) > w:
            rows.append(cur); cur = item
        else:
            cur = f"{cur}   {item}" if cur else item
    rows.append(cur)
    return rows
