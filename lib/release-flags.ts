// Enable only after the format-4 phone build is available to every syncing user.
export const native_format_four = process.env.NEXT_PUBLIC_NATIVE_FORMAT4_ENABLED === "true";

// Enable only after the format-5 phone build with Every, calculated rewards, and usage history is available.
export const native_format_five = process.env.NEXT_PUBLIC_NATIVE_FORMAT5_ENABLED === "true";

// Enable only after the format-6 phone build with once-per-code screen time is available.
export const native_format_six = process.env.NEXT_PUBLIC_NATIVE_FORMAT6_ENABLED === "true";
