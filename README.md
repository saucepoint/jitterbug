## JITTERBUG: Just-in-time Liquidity Positions via Hooks or Swap Router

# :construction: UNDER CONSTRUCTION :construction: 

> *Reusable abstract contracts, for creating JIT liquidity from any capital source*

---

![image](https://github.com/user-attachments/assets/9fcedd69-758c-4f0b-9895-ed7d6e824115)

---

```
jitterbug/
├── src
│   ├── JITRouter.sol   # (theoretical) Swap router which creates a JIT position on any Uniswap v4 Pool
│   ├── JIT.sol         # Base contract for creating and closing liquidity positions
│   ├── JITHook.sol     # Inherits JIT.sol to create positions in beforeSwap and close positions in afterSwap
│   └── examples
│       └── Simple.sol  # Inherits JITHook.sol that sources liquidity from an approving EOA address
```
