# Proposal: Shift-select → auto translate (Windows Terminal)

## Goal

When the user **Shift-selects text in Windows Terminal** and releases the mouse, **translate immediately** via Pot Forge — **no Alt+Q**.

## Previous behavior

1. Shift-drag to select  
2. Press **Alt+Q**  
3. Helper copies selection (`Ctrl+Shift+C`) → `POST /translate`

## New behavior

1. Shift-drag to select in Terminal  
2. On **left mouse button release** (selection finished) → auto copy + translate  
3. **Alt+Q** remains as manual fallback (optional)

## Detection rules

| Signal | Role |
|--------|------|
| Foreground process is Terminal (`WindowsTerminal` / Preview / `OpenConsole`) | Scope |
| `Shift` held while left button down | User is extending/making a selection |
| Left button **up** | Selection finished → trigger |

## Anti-noise

- Debounce **400ms** between auto-triggers  
- Ignore empty selection / copy failure  
- Ignore if selection text equals last translated text (same string)  
- Do **not** trigger on Shift alone (typing capitals) without mouse drag  
- Minimum drag: left button must have been down ≥ **80ms** while Shift held  

## Pipeline

```
LButton up + was Shift-select in Terminal
  → Ctrl+Shift+C (copy selection)
  → if non-empty text
  → POST http://127.0.0.1:60828/translate
  → Pot Forge translate window
```

## Non-goals

- Auto-translate in every app (only Terminal hosts listed)  
- Continuous clipboard monitoring  
- Replacing OCR / in-app selection for non-Terminal apps  

## Rollout

1. Implement in `PotTerminalHelper.ps1`  
2. Restart helper (startup lnk unchanged)  
3. User tests: Shift-select in Windows Terminal → window opens  

## Status

Approved by requirement update — implementing now.
