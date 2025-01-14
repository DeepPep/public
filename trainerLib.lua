--[[ Description: functions used for training of nn]]
require 'nn'
require 'optim'
local myUtil = require("../MyCommon/util.lua")

do
  local trainerLib = {}

  -- Input(nRows): batch size (currently allways full batch).
  -- Input(strOptimMethod): method used for optimization
  -- Input(nMaxIteration): maximum number of iterations
  function trainerLib.getDefaultTrainParams(nRows, strOptimMethod, nMaxIteration)

    local taTrainParam = {  batchSize = nRows and math.floor(nRows),
                            criterion = nn.MSECriterion(),
                            nMaxIteration = nMaxIteration or 10,
                            coefL1 = 0.0,
                            coefL2 = 0.0,
                            strOptimMethod = strOptimMethod or "CG",
                            isLog = true,
                            taOptimParams = {}
                          }

    if taTrainParam.strOptimMethod == "SGD" then
      taTrainParam.taOptimParams = { 
        learningRate = 1.0,
        --learningRateDecay = 0.1,
        momentum = 0.9 }
      taTrainParam.fuOptim = optim.sgd
  
    elseif taTrainParam.strOptimMethod == "LBFGS" then
      taTrainParam.taOptimParams = { 
        maxIter = 100,
        lineSearch = optim.lswolfe }
      taTrainParam.fuOptim = optim.lbfgs

    elseif taTrainParam.strOptimMethod == "CG" then
      taTrainParam.taOptimParams = {
        maxIter = 30 }
      taTrainParam.fuOptim = optim.cg
      
    elseif taTrainParam.strOptimMethod == "AdaGrad" then
      taTrainParam.taOptimParams = {
        learningRate = 0.5 }
      taTrainParam.fuOptim = optim.adagrad
      
    elseif taTrainParam.strOptimMethod == "RMSprop" then
      taTrainParam.taOptimParams = {
        learningRate = 0.5 }
      taTrainParam.fuOptim = optim.rmsprop

    else
      error("invalid operation")
    end

    return taTrainParam
  end

  -- Description: performs single round of training (using any provided optim method).
  -- Input(mNet): nn main object
  -- Input(taX): the nn input
  -- Input(taY): the nn target
  -- Input(taTrainParam): the training praramters
  function trainerLib.pri_trainSparseInputNet_SingleRound(mNet, taX, teY, taTrainParam)
    parameters, gradParameters = mNet:getParameters()
    local criterion = taTrainParam.criterion
    local overallErr = 0
    local scale = taTrainParam.taOptimParams.learningRate or 1

      local fuEval = function(x)
        collectgarbage()

        -- get new parameters
        if x ~= parameters then
          parameters:copy(x)
        end

        -- reset gradients
        gradParameters:zero()

        -- evaluate function for the complete mini batch
        local tePredY = mNet:forward(taX)
        local f = criterion:forward(tePredY, teY)

        -- estimate df/dW
        local df_do = criterion:backward(tePredY, teY, scale)
        mNet:backward(taX, df_do, scale)

       -- penalties (L1 and L2):
        if taTrainParam.coefL1 ~= 0 or taTrainParam.coefL2 ~= 0 then
          -- locals:
           local norm,sign= torch.norm,torch.sign
 
          -- Loss:
          f = f + taTrainParam.coefL1 * norm(parameters,1)
          f = f + taTrainParam.coefL2 * norm(parameters,2)^2/2

          -- Gradients:
          gradParameters:add( sign(parameters):mul(taTrainParam.coefL1) + parameters:clone():mul(taTrainParam.coefL2) )
        end

        return f, gradParameters
      end --fuEval

      taTrainParam.fuOptim(fuEval, parameters, taTrainParam.taOptimParams)

    return trainerLib.getErr(mNet, taX, teY, taTrainParam)
  end

  function trainerLib.getErr(mNet, taInput, teTarget, taTrainParam)
    local criterion = taTrainParam.criterion

    local teOutput = mNet:forward(taInput)
    local criterion = nn.MSECriterion()
    local fErr = criterion:forward(teOutput, teTarget)

    return fErr
  end

  -- Description: train nn
  function trainerLib.trainSparseInputNet(mNet, taInput, teTarget, nMaxIteration, strOptimMethod, isEarlyStop, dStopError, taTrainParam)
    strOptimMethod = strOptimMethod or "SGD"
    local criterion = nn.MSECriterion()
    local taTrainParam = taTrainParam or trainerLib.getDefaultTrainParams(teTarget:size(1), strOptimMethod, nMaxIteration )

    local errPrev = math.huge
    local errCurr = math.huge
    local errBest = math.huge
    teParameters, teGradParameters = mNet:getParameters()
    local teParametersBest = torch.Tensor(teParameters:size())
    local dMinDiffToUpdate = 0.0000001

    for i=1, taTrainParam.nMaxIteration do
      errCurr = trainerLib.pri_trainSparseInputNet_SingleRound(mNet, taInput, teTarget, taTrainParam)

      if isEarlyStop and (errPrev <= errCurr or myUtil.isNan(errCurr))  then
        print("** early stop **")
        return errPrev
      end

      if errCurr < (errBest - dMinDiffToUpdate) then -- updating only if minimum dMinDiffToUpdate improvement
        print("updateing, error: " .. errCurr)
        teParameters, teGradParameters = mNet:getParameters()
        teParametersBest:copy(teParameters)
        errBest = errCurr
      end

      if errCurr ~= nil and errCurr < math.huge then
        local message = errCurr < errPrev and "<" or "!>"
        myUtil.log(message, false, taTrainParam.isLog)
        myUtil.log(errCurr, false, taTrainParam.isLog)
        errPrev = errCurr
      else
        print(string.format("!!!! %s !!!!", tostring(errCurr)))
        error("invalid value for errCurr!")
      end

      if dStopError ~= nil and errCurr < dStopError then
        print(string.format("Reached error bellow: %f, therefore enough!", dStopError ))
        break
      end
    end

    teParameters, teGradParameters = mNet:getParameters()
    teParameters:copy(teParametersBest)

    return errBest
  end

  return trainerLib
end
