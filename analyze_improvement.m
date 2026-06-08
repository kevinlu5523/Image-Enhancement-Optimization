function markedImage = analyze_improvement(inputImage, outputImage)
    % --- 輸入參數 ---
    brisqueThreshold = 3; % BRISQUE 分數差值閾值
    gridSize = 8; % 網格大小
    
    % --- 分成 8x8 網格 ---
    [M, N, ~] = size(inputImage);
    blockHeight = floor(M / gridSize);
    blockWidth = floor(N / gridSize);
    improvedRegions = []; % 儲存畫質改善區域 [x, y, brisqueDiff]

    for i = 1:gridSize
        for j = 1:gridSize
            yStart = (i-1) * blockHeight + 1;
            yEnd = min(i * blockHeight, M);
            xStart = (j-1) * blockWidth + 1;
            xEnd = min(j * blockWidth, N);
            
            inputBlock = inputImage(yStart:yEnd, xStart:xEnd, :);
            outputBlock = outputImage(yStart:yEnd, xStart:xEnd, :);
            
            if isempty(inputBlock) || isempty(outputBlock)
                continue;
            end
            
            try
                brisqueInput = brisque(inputBlock);
                brisqueOutput = brisque(outputBlock);
            catch
                continue; % 計算失敗則跳過
            end
            
            brisqueDiff = brisqueInput - brisqueOutput;
            
            if brisqueDiff > brisqueThreshold
                improvedRegions(end+1, :) = [xStart, yStart, brisqueDiff];
            end
        end
    end

    % --- 可視化結果 (在記憶體中繪製) ---
    f = figure('Visible', 'off', 'Position', [100, 100, N, M]);
    ax = axes('Parent', f, 'Position', [0 0 1 1]);
    
    % 顯示「強化後」的影像
    imshow(outputImage, 'Parent', ax);
    hold(ax, 'on');
    
    for k = 1:size(improvedRegions, 1)
        x = improvedRegions(k, 1);
        y = improvedRegions(k, 2);
        brisqueDiff = improvedRegions(k, 3);
        
        rectangle(ax, 'Position', [x, y, blockWidth, blockHeight], ...
                  'EdgeColor', 'r', 'LineWidth', 2);
        
        label = sprintf('Diff: %.2f', brisqueDiff);
        text(ax, x+2, y+15, label, 'Color', 'y', 'FontSize', 10, 'FontWeight', 'bold', ...
             'BackgroundColor', 'k', 'Margin', 1);
    end
    hold(ax, 'off');
    
    % 從 figure 抓取影像幀
    frame = getframe(ax);
    markedImage = frame.cdata;
    
    % 關閉不可見的 figure
    close(f);
end