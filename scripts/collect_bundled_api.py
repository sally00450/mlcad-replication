#!/usr/bin/python3
# collect_bundled_api.py -- Collect 3 Bedrock responses for the bundled
# prompt PB (all 4 modules in one SV file).
#
# Usage:
#   scripts/collect_bundled_api.py --model us.anthropic.claude-opus-4-7 \
#                                  --outdir claude_api
#   scripts/collect_bundled_api.py --model us.anthropic.claude-opus-4-6-v1 \
#                                  --outdir claude46_api
#
# Responses are written to:
#   paper/web_ai_eval/responses/bundled/<outdir>/<outdir>_PB_trial{1,2,3}.sv
import argparse, os, re, sys, json, time, datetime
import boto3

PROMPTS_MD = "paper/web_ai_eval/PROMPTS_BUNDLED.md"
PROMPT_IDS = ["PB"]
TRIALS = [1, 2, 3]


def extract_prompt(md_text, pid):
    # PB header is "## PB -- ..." ; prompt runs until end of file.
    pattern = r"## " + re.escape(pid) + r" -- [^\n]+\n(.*)\Z"
    m = re.search(pattern, md_text, re.DOTALL)
    if not m:
        raise RuntimeError("prompt not found: " + pid)
    return m.group(1).strip()


def call_bedrock(client, model_id, prompt_text, max_tokens=32000):
    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": max_tokens,
        "temperature": 1.0,
        "messages": [{"role": "user", "content": prompt_text}],
    }
    resp = client.invoke_model(
        modelId=model_id,
        body=json.dumps(body),
        contentType="application/json",
        accept="application/json",
    )
    payload = json.loads(resp["body"].read())
    blocks = payload.get("content", [])
    text_parts = [b["text"] for b in blocks if b.get("type") == "text"]
    return "\n".join(text_parts)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", required=True)
    ap.add_argument("--outdir", required=True,
                    help="subdir under responses/bundled/ and filename prefix")
    ap.add_argument("--region", default="us-east-1")
    ap.add_argument("--prefix", default=None)
    args = ap.parse_args()

    prefix = args.prefix or args.outdir
    out_root = os.path.join("paper/web_ai_eval/responses/bundled", args.outdir)
    os.makedirs(out_root, exist_ok=True)

    with open(PROMPTS_MD) as f:
        md = f.read()

    m = args.model
    if not m.startswith("us."):
        if m.startswith("anthropic."):
            m = "us." + m
        else:
            m = "us.anthropic." + m
    model_id = m

    from botocore.config import Config
    bedrock_config = Config(read_timeout=600, connect_timeout=60,
                            retries={"max_attempts": 3})
    client = boto3.client("bedrock-runtime", region_name=args.region,
                          config=bedrock_config)

    with open(os.path.join(out_root, "model_info.txt"), "w") as f:
        f.write("bedrock_model_id: " + model_id + "\n")
        f.write("region: " + args.region + "\n")
        f.write("collected: " + datetime.datetime.now().isoformat() + "\n")
        f.write("temperature: 1.0\n")
        f.write("max_tokens: 32000\n")
        f.write("surface: Bedrock API (boto3)\n")
        f.write("prompt_file: " + PROMPTS_MD + "\n")

    total = len(PROMPT_IDS) * len(TRIALS)
    done = 0
    start = time.time()
    for pid in PROMPT_IDS:
        prompt_text = extract_prompt(md, pid)
        for trial in TRIALS:
            done += 1
            out_file = os.path.join(out_root,
                                    prefix + "_" + pid + "_trial"
                                    + str(trial) + ".sv")
            if os.path.exists(out_file):
                print("[{0}/{1}] SKIP exists: {2}".format(done, total,
                                                          out_file))
                continue
            t0 = time.time()
            try:
                text = call_bedrock(client, model_id, prompt_text)
            except Exception as e:
                print("[{0}/{1}] ERROR {2} trial {3}: {4}".format(
                    done, total, pid, trial, e), file=sys.stderr)
                continue
            with open(out_file, "w") as f:
                f.write(text)
            dt = time.time() - t0
            print("[{0}/{1}] {2} trial {3}: {4} bytes in {5:.1f}s -> {6}"
                  .format(done, total, pid, trial, len(text), dt, out_file))

    print("Done. Total: {0:.1f}s".format(time.time() - start))


if __name__ == "__main__":
    main()
