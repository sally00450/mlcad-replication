#!/usr/bin/python3
# collect_axi_nocontract_api.py -- Third-DUT (AXI4-Lite) NO-PORT-CONTRACT variant.
# Collects n=3 cloud-hosted LLM API responses for PS_AXI with the port-contract block
# removed (ablation baseline).
import argparse, os, re, sys, json, time, datetime
import boto3

PROMPTS_MD = os.path.join(os.path.dirname(__file__), "..",
                          "prompts", "PROMPTS_AXI_NOCONTRACT.md")
PROMPT_IDS = ["PS_AXI"]
TRIALS = list(range(1, 11))


def extract_prompt(md_text, pid):
    pattern = r"## " + re.escape(pid) + r" -- [^\n]+\n(.*?)(?=\n---\n|\n## |\Z)"
    m = re.search(pattern, md_text, re.DOTALL)
    if not m:
        raise RuntimeError("prompt not found: " + pid)
    return m.group(1).strip()


def call_api(client, model_id, prompt_text, max_tokens=16000):
    body = {
        "anthropic_version": "api-2023-05-31",
        "max_tokens": max_tokens,
        "temperature": 1.0,
        "messages": [{"role": "user", "content": prompt_text}],
    }
    resp = client.invoke_model(
        modelId=model_id, body=json.dumps(body),
        contentType="application/json", accept="application/json")
    payload = json.loads(resp["body"].read())
    blocks = payload.get("content", [])
    return "\n".join(b["text"] for b in blocks if b.get("type") == "text")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--model", default="<MODEL_ID_4_7>")
    ap.add_argument("--outdir", default="claude_api_nocontract")
    ap.add_argument("--region", default=os.environ.get("AWS_REGION", "us-west-2"))
    args = ap.parse_args()

    out_root = os.path.join(os.path.dirname(__file__), "..",
                            "responses_nocontract", args.outdir)
    os.makedirs(out_root, exist_ok=True)

    with open(PROMPTS_MD) as f:
        md = f.read()

    m = args.model
    if not m.startswith("us."):
        m = "us." + m if m.startswith("anthropic.") else "<API_PREFIX>." + m
    model_id = m

    from botocore.config import Config
    cfg = Config(read_timeout=600, connect_timeout=60,
                 retries={"max_attempts": 3})
    client = boto3.client("cloud-runtime", region_name=args.region,
                          config=cfg)

    with open(os.path.join(out_root, "model_info.txt"), "w") as f:
        f.write("model_id: " + model_id + "\n")
        f.write("region: " + args.region + "\n")
        f.write("collected: " + datetime.datetime.now().isoformat() + "\n")
        f.write("temperature: 1.0\nmax_tokens: 16000\n")
        f.write("surface: cloud-hosted LLM API API (boto3)\n")
        f.write("prompt_file: " + PROMPTS_MD + "\n")
        f.write("trials_per_prompt: " + str(len(TRIALS)) + "\n")
        f.write("variant: NO_PORT_CONTRACT (PS_AXI^nc)\n")

    start = time.time()
    for pid in PROMPT_IDS:
        prompt_text = extract_prompt(md, pid)
        for trial in TRIALS:
            out_file = os.path.join(
                out_root, args.outdir + "_" + pid + "_trial" + str(trial)
                + ".sv")
            if os.path.exists(out_file):
                print("SKIP exists:", out_file)
                continue
            t0 = time.time()
            try:
                text = call_api(client, model_id, prompt_text)
            except Exception as e:
                print("ERROR", pid, "trial", trial, ":", e, file=sys.stderr)
                continue
            with open(out_file, "w") as f:
                f.write(text)
            print("{0} trial {1}: {2} bytes in {3:.1f}s -> {4}".format(
                pid, trial, len(text), time.time() - t0, out_file))
    print("Done. Total: {0:.1f}s".format(time.time() - start))


if __name__ == "__main__":
    main()
