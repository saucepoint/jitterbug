## JITTERBUG: Just-in-time Liquidity Positions via Hooks or Swap Router

# :construction: UNDER CONSTRUCTION :construction: 

---

![image](https://github.com/user-attachments/assets/066383c4-7ad8-4703-820b-802af74a5dca)

---

```
jitterbug/
├── src
│   ├── JITRouter.sol   # (theoretical) Swap router which creates a JIT position on any Uniswap v4 Pool
│   ├── JIT.sol         # Base contract for creating and closing liquidity positions
│   ├── JITHook.sol     # Inherits JIT.sol to create positions in beforeSwap and close positions in afterSwap
│   └── examples
│       └── Simple.sol  # Inherits JITHook.sol to specify the capital source
```
