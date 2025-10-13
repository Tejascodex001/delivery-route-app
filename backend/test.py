import paddle

# Check if the installed PaddlePaddle package is compiled with CUDA support.
is_compiled_with_cuda = paddle.device.is_compiled_with_cuda()
print(f"PaddlePaddle package compiled with CUDA: {is_compiled_with_cuda}")

if is_compiled_with_cuda:
    # Get the number of available GPU devices using the correct API.
    try:
        gpu_count = paddle.device.cuda.device_count()
        print(f"Number of detected GPU devices: {gpu_count}")
        if gpu_count > 0:
            print("A GPU is available for use at runtime.")

            # Run a full health check.
            print("\nRunning PaddlePaddle installation health check...")
            paddle.utils.run_check()
        else:
            print("No GPU devices were detected at runtime.")
            print("Check your NVIDIA drivers and CUDA installation.")
    except Exception as e:
        print(f"An error occurred while checking GPU devices: {e}")
else:
    print("This PaddlePaddle package is not configured for GPU support.")
    print("You may need to install the `paddlepaddle-gpu` version.")
