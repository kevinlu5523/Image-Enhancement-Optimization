function [enhancedImage, best_a, best_b, best_fitness] = run_mpa_optimization(inputImage, metric)
    % 根據 metric 決定優化目標 (PCQI 越大越好, BRISQUE 越小越好)
    % 我們統一將適應度 (fitness) 設為最大化問題
    
    % 檢查 GPU
    useGPU = ~isempty(gpuDevice);
    if useGPU
        inputImageNorm = gpuArray(double(inputImage) / 255);
        inputGray = gpuArray(double(rgb2gray(inputImage)));
    else
        inputImageNorm = double(inputImage) / 255;
        inputGray = double(rgb2gray(inputImage));
    end

    % --- MPA 優化參數 a 和 b（針對公式 3） ---
    colorSpace = 'HSV'; % 鎖定使用 HSV
    nPop = 30; % 掠食者數量
    Max_iter = 20; % 迭代次數
    dim = 2; % 優化變數數量 (a 和 b)
    lb = [1, 0.01]; % 下界
    ub = [100, 3]; % 上界
    P = 0.5;
    FADS = 0.1;

    % 初始化
    if useGPU
        Prey = gpuArray(zeros(nPop, dim));
    else
        Prey = zeros(nPop, dim);
    end
    
    for i = 1:nPop
        Prey(i, :) = lb + (ub - lb) .* rand(1, dim);
    end
    Predator = Prey;
    
    if useGPU
        Elite = gpuArray(zeros(1, dim));
    else
        Elite = zeros(1, dim);
    end
    Elite_fitness = -inf; % 初始適應度 (最大化問題)

    % 迭代優化
    for iter = 1:Max_iter
        for i = 1:nPop
            % 確保參數在範圍內
            Prey(i, :) = max(Prey(i, :), lb);
            Prey(i, :) = min(Prey(i, :), ub);
            
            % 提取 a 和 b
            a = Prey(i, 1);
            b = Prey(i, 2);
            
            % 根據色彩空間處理影像（使用公式 3）
            hsvImage = rgb2hsv(inputImageNorm);
            x = hsvImage(:,:,3);
            y3 = log(1 + a * (x.^b)) / log(1 + a); % 公式 3
            y3 = max(0, min(1, y3));
            hsvImage3 = hsvImage; hsvImage3(:,:,3) = y3;
            
            if useGPU
                outputImage3_rgb = hsv2rgb(hsvImage3);
                outputImage3_uint8 = uint8(gather(outputImage3_rgb * 255));
            else
                outputImage3_rgb = hsv2rgb(hsvImage3);
                outputImage3_uint8 = uint8(outputImage3_rgb * 255);
            end

            % --- 根據 metric 計算適應度 ---
            if strcmpi(metric, 'PCQI')
                outputGray3 = rgb2gray(outputImage3_rgb);
                if useGPU
                    [fitness, ~] = PCQI(gather(inputGray), gather(outputGray3));
                else
                    [fitness, ~] = PCQI(inputGray, outputGray3);
                end
                fitness = double(fitness);
            
            else % 'BRISQUE'
                brisque_score = brisque(outputImage3_uint8);
                fitness = -brisque_score; % BRISQUE 越小越好，故取負值
            end
            
            % 更新 Elite Matrix
            if fitness > Elite_fitness
                Elite_fitness = fitness;
                Elite = Prey(i, :);
            end
        end
        
        % --- MPA 三階段更新 ---
        current_iter = iter / Max_iter; 
        if useGPU
            RB = gpuArray(rand(nPop, dim)); 
            RL = gpuArray(0.5 * (rand(nPop, dim) - 0.5));
            stepsize = gpuArray(zeros(nPop, dim));
        else
            RB = rand(nPop, dim); 
            RL = 0.5 * (rand(nPop, dim) - 0.5);
            stepsize = zeros(nPop, dim);
        end
        
        CF = (1 - iter / Max_iter)^(2 * iter / Max_iter);
        
        for i = 1:nPop
            for j = 1:dim
                R = rand();
                if current_iter < 1/3
                    stepsize(i, j) = RB(i, j) * (Elite(j) - RB(i, j) * Prey(i, j));
                    Predator(i, j) = Prey(i, j) + P * stepsize(i, j);
                elseif current_iter >= 1/3 && current_iter < 2/3
                    if i <= nPop / 2
                        stepsize(i, j) = RB(i, j) * (Elite(j) - RB(i, j) * Prey(i, j));
                        Predator(i, j) = Prey(i, j) + P * stepsize(i, j);
                    else
                        stepsize(i, j) = RL(i, j) * (RL(i, j) * Elite(j) - Prey(i, j));
                        Predator(i, j) = Elite(j) + P * CF * stepsize(i, j);
                    end
                else
                    stepsize(i, j) = RL(i, j) * (RL(i, j) * Elite(j) - Prey(i, j));
                    Predator(i, j) = Elite(j) + P * CF * stepsize(i, j);
                end
                if rand() < FADS
                    U = rand() < 0.5;
                    r = rand();
                    if U
                        Predator(i, j) = lb(j) + r * (ub(j) - lb(j));
                    else
                        r1 = rand();
                        r2 = rand();
                        Predator(i, j) = Predator(i, j) + (r1 * (ub(j) - lb(j)) * r2);
                    end
                end
            end
        end
        Prey = Predator; 
        % --- MPA 更新結束 ---
    end
    
    % 獲取最佳參數
    if useGPU
        best_a = gather(Elite(1));
        best_b = gather(Elite(2));
    else
        best_a = Elite(1);
        best_b = Elite(2);
    end
    
    best_fitness = Elite_fitness; % 回傳適應度分數

% --- 使用最佳參數生成最終強化影像 (公式 3) ---
% (此區塊先產生 100% 的強化影像)
hsvImage = rgb2hsv(inputImageNorm);
x = hsvImage(:,:,3);
y_final = log(1 + best_a * (x.^best_b)) / log(1 + best_a); % 公式 3
y_final = max(0, min(1, y_final));
hsvImage(:,:,3) = y_final;

if useGPU
    outputImage3_uint8 = uint8(gather(hsv2rgb(hsvImage) * 255));
else
    outputImage3_uint8 = uint8(hsv2rgb(hsvImage) * 255);
end

% --- 【關鍵修正】---
% 根據 metric (由 App 傳入) 決定是否混合
% metric 變數在函數開頭 (Line 1) 就已經傳入了

if strcmpi(metric, 'PCQI')
    % 【PCQI 路徑】：亮度 > 40，套用 50% 混合 (比照 mpa_PCQI.m)
    alpha = 0.7; % 來自您 mpa_PCQI.m (Line 38) 的設定
    
    if useGPU
        inputImageGPU = gpuArray(double(inputImage)); 
        outputImage3GPU = gpuArray(double(outputImage3_uint8));
        blendedImage_gpu = alpha * inputImageGPU + (1 - alpha) * outputImage3GPU;
        enhancedImage = uint8(gather(blendedImage_gpu));
    else
        % CPU 版本
        blendedImage = alpha * double(inputImage) + (1 - alpha) * double(outputImage3_uint8);
        enhancedImage = uint8(blendedImage);
    end
    
else
    % 【BRISQUE 路徑】：亮度 <= 40，不混合
    % 直接回傳 100% 強化的影像
    enhancedImage = outputImage3_uint8;
end
end