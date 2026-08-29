function f = peukert_factor(bat,I_mA)
%PEUKERT_FACTOR Effective-energy multiplier for load-rate derating.
    f = max(1,(max(I_mA,eps)/bat.I_ref_mA)^(bat.n-1));
end
