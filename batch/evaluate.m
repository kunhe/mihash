function res = evaluate(Htrain, Htest, Ytrain, Ytest, opts, Aff)
% input: 
%   Htrain - (logical) training binary codes
%   Htest  - (logical) testing binary codes
%   Ytrain - (int32) training labels
%   Ytest  - (int32) testing labels
% output:
%  mAP - mean Average Precision
if nargin < 6, Aff = []; end
hasAff = ~isempty(Aff);

if ~opts.unsupervised
    trainsize = length(Ytrain);
    testsize  = length(Ytest);
else
    [trainsize, testsize] = size(Aff);
end

if strcmp(opts.metric, 'mAP')
    sim = compare_hash_tables(Htrain, Htest);
    AP  = zeros(1, testsize);
    for j = 1:testsize
        labels = 2 * Aff(:, j) - 1;
        [~, ~, info] = vl_pr(labels, double(sim(:, j)));
        AP(j) = info.ap;
    end
    res = mean(AP(~isnan(AP)));
    logInfo(['mAP = ' num2str(res)]);

elseif ~isempty(strfind(opts.metric, 'mAP_'))
    % eval mAP on top N retrieved results
    assert(isfield(opts, 'mAP') & opts.mAP > 0);
    assert(opts.mAP < trainsize);
    N   = opts.mAP;
    sim = compare_hash_tables(Htrain, Htest);
    AP  = zeros(1, testsize);
    for j = 1:testsize
        sim_j = double(sim(:, j));
        idx = [];
        for th = opts.nbits:-1:-opts.nbits
            idx = [idx; find(sim_j == th)];
            if length(idx) >= N, break; end
        end
        idx = idx(1:N);
        labels = 2 * Aff(idx, j) - 1;
        [~, ~, info] = vl_pr(labels, sim_j(idx));
        AP(j) = info.ap;
    end
    res = mean(AP(~isnan(AP)));
    logInfo('mAP@(N=%d) = %g', N, res);

elseif ~isempty(strfind(opts.metric, 'prec_k'))
    % intended for PLACES, large scale
    K = opts.prec_k;
    sim = compare_hash_tables(Htrain, Htest);
    prec_k = zeros(1, testsize);
    for j = 1:testsize
        labels = Aff(:, j);
        [~, I] = sort(sim(:, j), 'descend');
        prec_k(i) = mean(labels(I(1:K)));
    end
    res = mean(prec_k);
    logInfo('Prec@(neighs=%d) = %g', K, res);

elseif ~isempty(strfind(opts.metric, 'prec_n'))
    N = opts.prec_n;
    R = opts.nbits;
    sim = compare_hash_tables(Htrain, Htest);
    prec_n = zeros(1, testsize);
    for j = 1:testsize
        labels = 2 * Aff(:, j) - 1;
        ind = find(R - sim(:,j) <= 2*N);
        if ~isempty(ind)
            prec_n(j) = mean(labels(ind));
        end
    end
    res = mean(prec_n);
    logInfo('Prec@(radius=%d) = %g', N, res);

else
    error(['Evaluation metric ' opts.metric ' not implemented']);
end
end

% ----------------------------------------------------------
function sim = compare_hash_tables(Htrain, Htest)
trainsize = size(Htrain, 2);
testsize  = size(Htest, 2);
if trainsize < 100e3
    sim = (2*single(Htrain)-1)'*(2*single(Htest)-1);
    sim = int8(sim);
else
    Ltest = 2*single(Htest)-1;
    sim = zeros(trainsize, testsize, 'int8');
    chunkSize = ceil(trainsize/10);
    for i = 1:ceil(trainsize/chunkSize)
        I = (i-1)*chunkSize+1 : min(i*chunkSize, trainsize);
        tmp = (2*single(Htrain(:,I))-1)' * Ltest;
        sim(I, :) = int8(tmp);
    end
    clear Ltest tmp
end
end


% ----------------------------------------------------------
function T = binsearch(x, k)
% x: input vector
% k: number of largest elements
% T: threshold
T = -Inf;
while numel(x) > k
    T0 = T;
    x0 = x;
    T  = mean(x);
    x  = x(x>T);
end
% for sanity
if numel(x) < k, T = T0; end
end