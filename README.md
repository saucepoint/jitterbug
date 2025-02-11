## JITTERBUG: Just-in-time Liquidity Positions via Hooks or Swap Router

# :construction: UNDER CONSTRUCTION :construction: 

> *Reusable abstract contracts, for creating JIT liquidity from any capital source*

---

_Automatically provisions JIT liquidity [with set token amounts](https://github.com/saucepoint/jitterbug/blob/main/src/examples/Simple.sol#L25-L35) on a [defined tick range](https://github.com/saucepoint/jitterbug/blob/main/src/examples/Simple.sol#L51-L59), using capital from an [arbitrary source](https://github.com/saucepoint/jitterbug/blob/main/src/examples/Simple.sol#L37-L43)_

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
