/**
 * ESBuild configuration for building individual TypeScript utility modules
 * for a Node.js environment. Builds are run concurrently for optimization.
 */
const { build } = require("esbuild");

// List of entry points (base names of the TypeScript files in src/).
const entryPoints = ["getModifyLiquidityResult", "getSqrtPriceAtTick", "getTickAtSqrtPrice"];

// Shared configuration applied to all build targets.
const sharedConfig = {
  bundle: true,        // Bundle all dependencies into a single file
  minify: false,       // Keep the output unminified (set to true for production)
  platform: "node",    // Target Node.js environment
};

/**
 * Executes the ESBuild process concurrently for all defined entry points.
 */
async function runBuilds() {
  const buildPromises = entryPoints.map((entryPoint) => {
    const inputFile = `src/${entryPoint}.ts`;
    const outputFile = `dist/${entryPoint}.js`;

    console.log(`Building: ${inputFile} -> ${outputFile}`);

    return build({
      entryPoints: [inputFile],
      ...sharedConfig,
      outfile: outputFile,
    });
  });

  try {
    // Run all builds concurrently and wait for all Promises to resolve.
    await Promise.all(buildPromises);
    console.log("✅ All builds completed successfully.");
  } catch (error) {
    console.error("❌ ESBuild failed during compilation:", error);
    process.exit(1); // Exit with a non-zero code on failure
  }
}

// Execute the main build function.
runBuilds();
