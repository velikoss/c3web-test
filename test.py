import json
import asyncio

process = None

async def load_config(config_file):
    with open(config_file, 'r') as f:
        return json.load(f)

async def update_workers(config, new_worker_count):
    config['workers'] = new_worker_count
    return config

async def save_config(config_file, config):
    with open(config_file, 'w') as f:
        json.dump(config, f, indent=4)

async def run_c3libuv():
    try:
        global process
        process = await asyncio.create_subprocess_exec(
            "./build/c3libuv",
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
    except Exception as e:
        print(f"Exception occurred while building c3libuv: {e}")
        return False
    return True

async def run_wrk_benchmark(thread_count):
    # Run the wrk benchmark command
    url = "http://localhost:8080"  # Change to your target URL
    command = ["../wrk/wrk", "-t", str(thread_count), "-c", "100", "-d", "10s", url]
    
    try:
        print(f"Running wrk benchmark with {thread_count} threads...")
        process = await asyncio.create_subprocess_exec(
            *command,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await process.communicate()
        
        if process.returncode == 0:
            print(f"wrk benchmark completed for {thread_count} threads.")
            print(list(set([i if i.lstrip().startswith("Requests/sec:") else "" for i in stdout.decode().strip().splitlines()]))[-1])
        else:
            print(f"Error running wrk benchmark with {thread_count} threads: {stderr.decode().strip()}")
    except Exception as e:
        print(f"Exception occurred while running wrk benchmark: {e}")

async def main():
    config_file = 'config.json'
    config = await load_config(config_file)
    
    initial_workers = config.get('workers', 1)
    
    for i in range(1, initial_workers + 1):
        # Update the config with the new worker count
        updated_config = await update_workers(config, i)
        await save_config(config_file, updated_config)
        
        # Rerun the c3libuv build
        print(f"Running c3libuv with {i} threads...")
        if not await run_c3libuv():
            print("Skipping wrk benchmark due to c3libuv build failure.")
            continue  # Skip to the next iteration if build fails
        
        # Run the wrk benchmark with the current number of threads
        for j in range(1, i + 1):
            await run_wrk_benchmark(j)
        process.kill()


if __name__ == "__main__":
    asyncio.run(main())
